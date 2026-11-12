import CSMC
import Foundation
import LambaCore
import SwiftUI

extension L10n {
    static let thermalsTemperatures = tr("thermals.temperatures")
    static let thermalsChip = tr("thermals.chip")
    static let thermalsChipHottest = tr("thermals.chipHottest")
    static let thermalsBattery = tr("thermals.battery")
    static let thermalsSSD = tr("thermals.ssd")
    static let thermalsFans = tr("thermals.fans")
    static let thermalsFanOff = tr("thermals.fanOff")
    static let thermalsAuto = tr("thermals.auto")
    static let thermalsMax = tr("thermals.max")
    static let thermalsCustom = tr("thermals.custom")
    static let thermalsFooter = tr("thermals.footer")
    static func thermalsFan(_ number: Int) -> String { format("thermals.fan", number) }
    static func thermalsRange(_ low: Int, _ high: Int) -> String { format("thermals.range", low, high) }
}

/// Fan speeds (SMC) and temperatures (HID sensors), read without root. Setting the fan speed goes
/// through the root helper; Lamba always starts on automatic and gives the fans back on quit.
final class Thermals: ObservableObject {
    static let shared = Thermals()

    struct Fan: Identifiable, Equatable {
        let index: Int
        var rpm: Double
        var min: Double
        var max: Double
        var id: Int { index }
        /// Share of the way from off to the maximum speed.
        var load: Double { max > 0 ? Swift.min(rpm / max, 1) : 0 }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case auto, max, custom
        var id: Self { self }
    }

    @Published private(set) var fans: [Fan] = []
    @Published private(set) var chip: Double?
    @Published private(set) var chipHottest: Double?
    @Published private(set) var battery: Double?
    @Published private(set) var ssd: Double?
    @Published private(set) var mode: Mode = .auto
    /// 0...1 between each fan's minimum and maximum, for `.custom`.
    @Published var customLevel: Double = 0.5
    @Published private(set) var error: String?
    /// macOS takes a few seconds to hand the fans over.
    @Published private(set) var applying = false

    private let sensors = TemperatureSensors()
    private var applyWork: DispatchWorkItem?

    var hasFans: Bool { !fans.isEmpty }

    func sample() {
        let count = Int(Self.readUInt8("FNum") ?? 0)
        fans = (0..<count).map { index in
            Fan(index: index,
                rpm: Double(Self.readFloat("F\(index)Ac") ?? 0),
                min: Double(Self.readFloat("F\(index)Mn") ?? 0),
                max: Double(Self.readFloat("F\(index)Mx") ?? 0))
        }
        let readings = sensors.read()
        let dies = readings.filter { $0.name.hasPrefix("PMU tdie") }.map(\.value)
        chip = dies.isEmpty ? nil : dies.reduce(0, +) / Double(dies.count)
        chipHottest = dies.max()
        battery = Self.average(readings.filter { $0.name.hasPrefix("gas gauge battery") }.map(\.value))
        ssd = Self.average(readings.filter { $0.name.hasPrefix("NAND") }.map(\.value))
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        apply()
    }

    func setCustomLevel(_ level: Double) {
        customLevel = level
        guard mode == .custom else { return }
        // Wait for the slider to settle.
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Called on quit.
    func releaseFans() {
        guard mode != .auto else { return }
        _ = try? HelperClient().send(.fans(level: nil), timeout: 3)
    }

    private func apply() {
        let level: Double? = mode == .auto ? nil : mode == .max ? 1 : customLevel
        applying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String?
            do {
                let response = try HelperClient().send(.fans(level: level), timeout: 12)
                message = response.ok ? nil : response.error
            } catch {
                message = "\(error)"
            }
            DispatchQueue.main.async {
                self.error = message
                self.applying = false
                if message != nil { self.mode = .auto }
            }
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func read(_ key: String) -> (bytes: [UInt8], type: String)? {
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0, type: UInt32 = 0
        guard lamba_smc_read_key(key, &bytes, &size, &type) == LAMBA_SMC_OK else { return nil }
        let name = String(bytes: [24, 16, 8, 0].map { UInt8((type >> $0) & 0xff) }, encoding: .ascii) ?? ""
        return (Array(bytes.prefix(Int(size))), name)
    }

    private static func readUInt8(_ key: String) -> UInt8? { read(key)?.bytes.first }

    private static func readFloat(_ key: String) -> Float? {
        guard let (bytes, type) = read(key) else { return nil }
        if type == "flt ", bytes.count == 4 { return bytes.withUnsafeBytes { $0.load(as: Float.self) } }
        if type == "fpe2", bytes.count == 2 { return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4 }
        return nil
    }
}

/// Apple silicon temperature sensors through IOHIDEventSystemClient (what `powermetrics` and
/// Stats read), looked up at runtime.
private final class TemperatureSensors {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    /// The services belong to the client; it has to outlive them.
    private let client: AnyObject?
    private let services: [(name: String, service: AnyObject)]
    private let copyEvent: CopyEvent?
    private let getFloat: GetFloat?

    init() {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            client = nil; services = []; copyEvent = nil; getFloat = nil
            return
        }
        func symbol<T>(_ name: String, _: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: T.self) } }
        copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEvent.self)
        getFloat = symbol("IOHIDEventGetFloatValue", GetFloat.self)
        guard let create = symbol("IOHIDEventSystemClientCreate", Create.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            client = nil
            services = []
            return
        }
        self.client = client
        // Apple vendor page, temperature sensors.
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let list = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        services = list.map { service in
            ((copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "", service)
        }
    }

    func read() -> [(name: String, value: Double)] {
        guard let copyEvent, let getFloat else { return [] }
        return services.compactMap { sensor in
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            let value = getFloat(event, Int32(Self.temperatureEvent << 16))
            return value > 0 && value < 150 ? (sensor.name, value) : nil
        }
    }
}

// MARK: - Popover section

struct ThermalsSection: View {
    @ObservedObject var thermals = Thermals.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            temperatures
            if thermals.hasFans { fans }
        }
    }

    private var temperatures: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.thermalsTemperatures).font(.system(size: 12, weight: .medium))
            HStack(alignment: .top, spacing: 6) {
                if let chip = thermals.chip { TempChip(title: L10n.thermalsChip, value: chip, hottest: thermals.chipHottest) }
                if let battery = thermals.battery { TempChip(title: L10n.thermalsBattery, value: battery) }
                if let ssd = thermals.ssd { TempChip(title: L10n.thermalsSSD, value: ssd) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fans: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.thermalsFans).font(.system(size: 12, weight: .medium))
                if thermals.applying { ProgressView().controlSize(.mini) }
                Spacer()
                Picker("", selection: Binding(get: { thermals.mode }, set: { thermals.setMode($0) })) {
                    Text(L10n.thermalsAuto).tag(Thermals.Mode.auto)
                    Text(L10n.thermalsMax).tag(Thermals.Mode.max)
                    Text(L10n.thermalsCustom).tag(Thermals.Mode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }
            ForEach(thermals.fans) { FanRow(fan: $0) }
            if thermals.mode == .custom {
                HStack(spacing: 8) {
                    Image(systemName: "fan").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { thermals.customLevel }, set: { thermals.setCustomLevel($0) }), in: 0...1)
                        .controlSize(.small)
                    Text("\(Int(thermals.customLevel * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
            }
            Text(thermals.error ?? L10n.thermalsFooter)
                .font(.system(size: 10.5))
                .foregroundStyle(thermals.error == nil ? Color.secondary : Theme.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TempChip: View {
    let title: String
    let value: Double
    var hottest: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))°")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            if let hottest {
                Text(L10n.thermalsChipHottest + " \(Int(hottest.rounded()))°")
                    .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var color: Color { value >= 90 ? .red : value >= 75 ? Theme.orange : .primary }
}

private struct FanRow: View {
    let fan: Thermals.Fan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan.fill")
                .font(.system(size: 12))
                .foregroundStyle(fan.rpm > 0 ? Color.accentColor : Color.secondary)
                .rotationEffect(.degrees(fan.rpm > 0 ? 360 : 0))
                .animation(fan.rpm > 0 ? .linear(duration: max(0.25, 1200 / fan.rpm)).repeatForever(autoreverses: false) : .default, value: fan.rpm > 0)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(L10n.thermalsFan(fan.index + 1)).font(.system(size: 11))
                    Spacer()
                    Text(fan.rpm > 0 ? "\(Int(fan.rpm)) rpm" : L10n.thermalsFanOff)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.accentColor).frame(width: max(2, proxy.size.width * fan.load))
                    }
                }
                .frame(height: 4)
                Text(L10n.thermalsRange(Int(fan.min), Int(fan.max)))
                    .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }
}
