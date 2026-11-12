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
    static func systemMemoryDetail(_ used: String, _ total: String) -> String { format("system.memoryDetail", used, total) }
}

/// CPU, memory and network use, sampled every two seconds while a Dock shows it.
final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var downPerSecond: Double = 0
    @Published private(set) var upPerSecond: Double = 0
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
        if let used = Self.memoryInUse() { memoryUsed = used }
        let bytes = Self.networkBytes(), now = Date()
        if let last = lastBytes {
            let seconds = max(now.timeIntervalSince(last.at), 0.1)
            downPerSecond = Double(bytes.down &- last.down) / seconds
            upPerSecond = Double(bytes.up &- last.up) / seconds
            if bytes.down < last.down || bytes.up < last.up { downPerSecond = 0; upPerSecond = 0 }
        }
        lastBytes = (bytes.down, bytes.up, now)
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

    /// Like Activity Monitor's "Memory Used": app memory, wired and compressed.
    private static func memoryInUse() -> UInt64? {
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
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
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
            }
            HStack {
                Text(L10n.systemNetwork).font(.system(size: 12, weight: .medium))
                Spacer()
                Label(SystemStatus.rate(status.downPerSecond), systemImage: "arrow.down")
                Label(SystemStatus.rate(status.upPerSecond), systemImage: "arrow.up")
            }
            .font(.system(size: 11.5).monospacedDigit())

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
