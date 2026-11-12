import AppKit
import Darwin
import SwiftUI

extension L10n {
    static let systemTitle = tr("system.title")
    static let systemCPU = tr("system.cpu")
    static let systemMemory = tr("system.memory")
    static let systemNetwork = tr("system.network")
    static let systemOpenMonitor = tr("system.openMonitor")
    static let systemShow = tr("system.show")
    static let systemLastHour = tr("system.lastHour")
    static let systemTotal = tr("system.total")
    static let systemMemApp = tr("system.mem.app")
    static let systemMemWired = tr("system.mem.wired")
    static let systemMemCompressed = tr("system.mem.compressed")
    static let systemMemCache = tr("system.mem.cache")
    static func systemMemoryDetail(_ used: String, _ total: String) -> String { format("system.memoryDetail", used, total) }
}

/// CPU, memory and network use, sampled every two seconds while a Dock shows it.
final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    struct MemoryParts: Equatable { var app: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cache: UInt64 = 0 }
    /// What "used" is made of, plus the file cache (not counted as used).
    @Published private(set) var memoryParts = MemoryParts()
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var downPerSecond: Double = 0
    @Published private(set) var upPerSecond: Double = 0
    /// Network use per minute over the last hour, oldest first; older minutes drop off.
    struct Minute: Equatable {
        let start: Date
        var down: UInt64
        var up: UInt64
    }
    @Published private(set) var networkMinutes: [Minute] = []
    var hourDown: UInt64 { networkMinutes.reduce(0) { $0 + $1.down } }
    var hourUp: UInt64 { networkMinutes.reduce(0) { $0 + $1.up } }

    /// Last minute of CPU use, oldest first.
    @Published private(set) var cpuHistory: [Double] = []

    var memory: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastBytes: (down: UInt64, up: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
                cpuHistory = Array((cpuHistory + [cpu]).suffix(30))
            }
            lastTicks = ticks
        }
        if let parts = Self.memoryParts() {
            memoryParts = parts
            memoryUsed = parts.app + parts.wired + parts.compressed
        }
        let bytes = Self.networkBytes(), now = Date()
        if let last = lastBytes {
            let seconds = max(now.timeIntervalSince(last.at), 0.1)
            if bytes.down >= last.down, bytes.up >= last.up {
                downPerSecond = Double(bytes.down - last.down) / seconds
                upPerSecond = Double(bytes.up - last.up) / seconds
                record(down: bytes.down - last.down, up: bytes.up - last.up, at: now)
            } else {
                // Counters reset (interface went away); skip this sample.
                downPerSecond = 0
                upPerSecond = 0
            }
        }
        lastBytes = (bytes.down, bytes.up, now)
    }

    private func record(down: UInt64, up: UInt64, at now: Date) {
        let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        var minutes = networkMinutes.filter { $0.start > now.addingTimeInterval(-3600) }
        if minutes.last?.start == minute {
            minutes[minutes.count - 1].down += down
            minutes[minutes.count - 1].up += up
        } else {
            minutes.append(Minute(start: minute, down: down, up: up))
        }
        networkMinutes = minutes
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Activity Monitor's breakdown: "Memory Used" is app memory, wired and compressed;
    /// cached files can be dropped at any time and aren't counted.
    private static func memoryParts() -> MemoryParts? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        return MemoryParts(
            app: app * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cache: (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
        )
    }

    /// Bytes through physical interfaces (en*), since boot.
    private static func networkBytes() -> (down: UInt64, up: UInt64) {
        var down: UInt64 = 0, up: UInt64 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.ifa_name).hasPrefix("en"),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down += UInt64(data.pointee.ifi_ibytes)
            up += UInt64(data.pointee.ifi_obytes)
        }
        return (down, up)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

// MARK: - Tile

/// Two thin gauges (CPU, memory) side by side; a click shows the details.
struct SystemStatusTile: View {
    @ObservedObject var status = SystemStatus.shared
    var onDark = false
    @State private var frame: CGRect = .zero

    private var ink: Color { onDark ? .white : .primary }

    var body: some View {
        Button {
            DockPopover.shared.toggle(id: "system", anchor: frame) { SystemStatusPopover(status: status) }
        } label: {
            HStack(spacing: 7) {
                gauge("CPU", status.cpu)
                gauge("RAM", status.memory)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.systemTitle)
        .accessibilityLabel("\(L10n.systemCPU) \(Int(status.cpu * 100))%, \(L10n.systemMemory) \(Int(status.memory * 100))%")
        .frame(maxHeight: .infinity)
        .modifier(AnchorReader(frame: $frame))
        .onAppear { status.start() }
    }

    private func gauge(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ink.opacity(0.9))
            Bar(value: value, track: ink.opacity(0.12)).frame(width: 30, height: 3)
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(ink.opacity(0.45))
        }
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// Green, then orange from 70 %, red from 90 %.
private func loadColor(_ value: Double) -> Color {
    value >= 0.9 ? .red : value >= 0.7 ? Theme.orange : .green
}

private struct Bar: View {
    let value: Double
    let track: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(loadColor(value)).frame(width: max(2, proxy.size.width * min(max(value, 0), 1)))
            }
        }
    }
}

// MARK: - Popover

struct SystemStatusPopover: View {
    @ObservedObject var status: SystemStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent").foregroundStyle(Color.accentColor)
                Text(L10n.systemTitle)
            }
            .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                row(L10n.systemCPU, "\(Int((status.cpu * 100).rounded()))%")
                Sparkline(values: status.cpuHistory).frame(height: 34)
            }
            VStack(alignment: .leading, spacing: 6) {
                row(L10n.systemMemory, L10n.systemMemoryDetail(bytes(status.memoryUsed), bytes(status.memoryTotal)))
                Bar(value: status.memory, track: Color.white.opacity(0.12)).frame(height: 6)
                memoryPart(L10n.systemMemApp, status.memoryParts.app)
                memoryPart(L10n.systemMemWired, status.memoryParts.wired)
                memoryPart(L10n.systemMemCompressed, status.memoryParts.compressed)
                memoryPart(L10n.systemMemCache, status.memoryParts.cache)
            }
            HStack {
                Text(L10n.systemNetwork).font(.system(size: 12, weight: .medium))
                Spacer()
                Label(SystemStatus.rate(status.downPerSecond), systemImage: "arrow.down")
                Label(SystemStatus.rate(status.upPerSecond), systemImage: "arrow.up")
            }
            .font(.system(size: 11.5).monospacedDigit())
            NetworkHour(status: status)

            Button {
                DockPopover.shared.close()
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            } label: {
                Text(L10n.systemOpenMonitor)
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280)
        .animation(.easeOut(duration: 0.4), value: status.cpu)
    }

    private func memoryPart(_ title: String, _ value: UInt64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(bytes(value)).monospacedDigit()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

/// The last minute of CPU use as a filled line.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05))
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                    }
                    .fill(Color.accentColor.opacity(0.18))
                    Path { path in path.addLines(points) }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let step = size.width / 29
        let offset = CGFloat(30 - values.count) * step
        return values.enumerated().map { index, value in
            CGPoint(x: offset + CGFloat(index) * step, y: size.height - 2 - CGFloat(min(max(value, 0), 1)) * (size.height - 4))
        }
    }
}

/// Totals for the last hour and a bar per minute (download up, upload down from the middle line).
private struct NetworkHour: View {
    @ObservedObject var status: SystemStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.systemLastHour).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(L10n.systemTotal) \(bytes(status.hourDown + status.hourUp))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            bars.frame(height: 40)
            HStack(spacing: 10) {
                legend(Color.accentColor, "arrow.down", bytes(status.hourDown))
                legend(Color.green, "arrow.up", bytes(status.hourUp))
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var bars: some View {
        GeometryReader { proxy in
            let minutes = status.networkMinutes
            let peak = max(minutes.map { max($0.down, $0.up) }.max() ?? 1, 1)
            let width = proxy.size.width / 60
            let half = proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5).offset(y: half)
                ForEach(Array(minutes.enumerated()), id: \.element.start) { index, minute in
                    let x = CGFloat(60 - minutes.count + index) * width
                    let down = max(1, half * CGFloat(Double(minute.down) / Double(peak)))
                    let up = max(1, half * CGFloat(Double(minute.up) / Double(peak)))
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor)
                        .frame(width: max(1, width - 1), height: down)
                        .offset(x: x, y: half - down)
                    RoundedRectangle(cornerRadius: 1).fill(Color.green.opacity(0.85))
                        .frame(width: max(1, width - 1), height: up)
                        .offset(x: x, y: half)
                }
            }
        }
    }

    private func legend(_ color: Color, _ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11).monospacedDigit())
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
