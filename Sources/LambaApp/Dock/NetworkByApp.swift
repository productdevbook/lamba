import AppKit
import Darwin

/// Which apps used the network most in the last hour.
///
/// Uses NetworkStatistics, the private framework behind `nettop` and Activity Monitor: the kernel
/// keeps per-connection byte counts, and one query every 15 s reads them without starting a
/// process. Only per-minute sums by app are kept; minutes older than an hour drop off.
final class NetworkByApp: ObservableObject {
    static let shared = NetworkByApp()

    struct Usage: Identifiable, Equatable {
        let name: String
        let bytes: UInt64
        let appURL: URL?
        var id: String { name }
    }

    @Published private(set) var top: [Usage] = []

    private typealias Manager = OpaquePointer
    private typealias Source = OpaquePointer
    private typealias Create = @convention(c) (CFAllocator?, DispatchQueue, @escaping @convention(block) (Source, UnsafeMutableRawPointer?) -> Void) -> Manager
    private typealias AddAll = @convention(c) (Manager, Int32, Int32) -> Void
    private typealias SetDictBlock = @convention(c) (Source, @escaping @convention(block) (CFDictionary) -> Void) -> Void
    private typealias SetVoidBlock = @convention(c) (Source, @escaping @convention(block) () -> Void) -> Void
    private typealias Query = @convention(c) (Manager, @escaping @convention(block) () -> Void) -> Void

    private struct Connection {
        var pid: pid_t = 0
        var name = ""
        var counted: UInt64 = 0
        var latest: UInt64 = 0
    }

    /// Touched only on `queue`.
    private var connections: [Source: Connection] = [:]
    private var pending: [String: UInt64] = [:]
    private var appNames: [pid_t: (name: String, url: URL?)] = [:]

    private var minutes: [(start: Date, bytes: [String: UInt64])] = []
    private var appURLs: [String: URL] = [:]

    private let queue = DispatchQueue(label: "dev.hamur.lamba.netstat")
    private var manager: Manager?
    private var timer: Timer?
    private var keys: (name: String, pid: String, rx: String, tx: String)?
    private var setCounts: SetDictBlock?
    private var setDescription: SetDictBlock?
    private var setRemoved: SetVoidBlock?
    private var queryCounts: Query?
    private var queryDescriptions: Query?

    func start() {
        guard manager == nil, let library = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_LAZY) else { return }
        func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        func key(_ name: String) -> String? { dlsym(library, name)?.assumingMemoryBound(to: CFString.self).pointee as String? }
        guard let create = symbol("NStatManagerCreate", Create.self),
              let addTCP = symbol("NStatManagerAddAllTCPWithFilter", AddAll.self),
              let addUDP = symbol("NStatManagerAddAllUDPWithFilter", AddAll.self),
              let name = key("kNStatSrcKeyProcessName"), let pid = key("kNStatSrcKeyPID"),
              let rx = key("kNStatSrcKeyRxBytes"), let tx = key("kNStatSrcKeyTxBytes") else { return }
        keys = (name, pid, rx, tx)
        setCounts = symbol("NStatSourceSetCountsBlock", SetDictBlock.self)
        setDescription = symbol("NStatSourceSetDescriptionBlock", SetDictBlock.self)
        setRemoved = symbol("NStatSourceSetRemovedBlock", SetVoidBlock.self)
        queryCounts = symbol("NStatManagerQueryAllSources", Query.self)
        queryDescriptions = symbol("NStatManagerQueryAllSourcesDescriptions", Query.self)

        let manager = create(kCFAllocatorDefault, queue) { [weak self] source, _ in self?.added(source) }
        addTCP(manager, 0, 0)
        addUDP(manager, 0, 0)
        self.manager = manager
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.poll() }
    }

    // MARK: On `queue`

    private func added(_ source: Source) {
        connections[source] = Connection()
        setDescription?(source) { [weak self] dictionary in self?.described(source, dictionary as NSDictionary) }
        setCounts?(source) { [weak self] dictionary in self?.counted(source, dictionary as NSDictionary) }
        setRemoved?(source) { [weak self] in self?.removed(source) }
    }

    private func described(_ source: Source, _ info: NSDictionary) {
        guard let keys, connections[source] != nil else { return }
        connections[source]?.pid = (info[keys.pid] as? NSNumber)?.int32Value ?? 0
        connections[source]?.name = info[keys.name] as? String ?? ""
    }

    private func counted(_ source: Source, _ info: NSDictionary) {
        guard let keys, connections[source] != nil else { return }
        let rx = (info[keys.rx] as? NSNumber)?.uint64Value ?? 0
        let tx = (info[keys.tx] as? NSNumber)?.uint64Value ?? 0
        connections[source]?.latest = rx + tx
    }

    private func removed(_ source: Source) {
        collect(source)
        connections[source] = nil
    }

    /// Moves a connection's bytes since the last poll into `pending`, under its app's name.
    private func collect(_ source: Source) {
        guard var connection = connections[source], connection.latest > connection.counted else { return }
        let delta = connection.latest - connection.counted
        connection.counted = connection.latest
        connections[source] = connection
        guard connection.pid != 0 || !connection.name.isEmpty else { return }
        pending[app(pid: connection.pid, fallback: connection.name).name, default: 0] += delta
    }

    private func app(pid: pid_t, fallback: String) -> (name: String, url: URL?) {
        if let known = appNames[pid] { return known }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var result: (String, URL?) = (fallback.isEmpty ? "?" : fallback, nil)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            // A helper or extension inside Foo.app belongs to Foo.app.
            if let range = path.range(of: ".app/") {
                let url = URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
                let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                result = (name, url)
            } else {
                result = (URL(fileURLWithPath: path).lastPathComponent, nil)
            }
        }
        appNames[pid] = result
        return result
    }

    // MARK: Polling

    private var primed = false

    private func poll() {
        guard let manager else { return }
        queryDescriptions?(manager) {}
        queryCounts?(manager) { [weak self] in
            guard let self else { return }
            if !self.primed {
                // The first counts reach back to each connection's start; use them as the baseline.
                for (source, connection) in self.connections { self.connections[source]?.counted = connection.latest }
                self.primed = true
                return
            }
            for source in self.connections.keys { self.collect(source) }
            let used = self.pending
            let urls = Dictionary(self.appNames.values.compactMap { app in app.url.map { (app.name, $0) } }, uniquingKeysWith: { a, _ in a })
            self.pending = [:]
            DispatchQueue.main.async { self.record(used, urls: urls) }
        }
    }

    private func record(_ used: [String: UInt64], urls: [String: URL]) {
        appURLs.merge(urls) { a, _ in a }
        let now = Date()
        let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        minutes = minutes.filter { $0.start > now.addingTimeInterval(-3600) }
        if minutes.last?.start == minute {
            minutes[minutes.count - 1].bytes.merge(used, uniquingKeysWith: +)
        } else {
            minutes.append((minute, used))
        }
        var sums: [String: UInt64] = [:]
        for minute in minutes { sums.merge(minute.bytes, uniquingKeysWith: +) }
        let top = sums.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5)
            .map { Usage(name: $0.key, bytes: $0.value, appURL: appURLs[$0.key]) }
        if top != self.top { self.top = top }
    }
}
