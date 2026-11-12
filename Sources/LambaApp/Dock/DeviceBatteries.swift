import Foundation
import IOKit.ps

/// Battery level of the Mac or a connected accessory (Magic Mouse/Keyboard/Trackpad, AirPods, …).
struct DeviceBattery: Identifiable, Equatable {
    enum Kind { case mac, mouse, keyboard, trackpad, headphones, gameController, other }

    let id: String
    let name: String
    let kind: Kind
    let percent: Int
    let isCharging: Bool

    var isLow: Bool { percent <= 20 && !isCharging }
    /// Worth showing in the Dock without being asked.
    var needsAttention: Bool { isLow || isCharging }

    var symbol: String {
        switch kind {
        case .mac: return "laptopcomputer"
        case .mouse: return "magicmouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "hand.point.up.left.fill"
        case .headphones: return "airpods"
        case .gameController: return "gamecontroller.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

enum DeviceBatteries {
    /// The Mac's battery first, then accessories by name.
    static func read() -> [DeviceBattery] {
        guard let info = copyAllSources() else { return [] }
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }

        var mac: DeviceBattery?
        // Accessories with several parts (AirPods buds and case) share an identifier; show the lowest.
        var accessories: [String: DeviceBattery] = [:]
        for description in descriptions {
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }
            let percent = current * 100 / max
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let name = description[kIOPSNameKey] as? String ?? ""

            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                mac = DeviceBattery(id: "mac", name: "Mac", kind: .mac, percent: percent, isCharging: isCharging)
                continue
            }
            let id = description["Accessory Identifier"] as? String ?? name
            let kind = kind(category: description["Accessory Category"] as? String, name: name)
            let battery = DeviceBattery(id: id, name: name, kind: kind, percent: percent, isCharging: isCharging)
            if let existing = accessories[id] {
                accessories[id] = DeviceBattery(
                    id: id, name: existing.name, kind: existing.kind,
                    percent: min(existing.percent, percent), isCharging: existing.isCharging || isCharging
                )
            } else {
                accessories[id] = battery
            }
        }
        return [mac].compactMap { $0 } + accessories.values.sorted { $0.name < $1.name }
    }

    /// All power sources including accessories. The public `IOPSCopyPowerSourcesInfo` only lists
    /// the Mac's own battery, so this prefers `IOPSCopyPowerSourcesByType(0)` (what `pmset -g accps`
    /// uses) when it is available.
    private static func copyAllSources() -> CFTypeRef? {
        typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        if let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
           let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType"),
           let info = unsafeBitCast(symbol, to: CopyByType.self)(0)?.takeRetainedValue() {
            return info
        }
        return IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
    }

    private static func kind(category: String?, name: String) -> DeviceBattery.Kind {
        let text = ((category ?? "") + " " + name).lowercased()
        if text.contains("mouse") { return .mouse }
        if text.contains("keyboard") { return .keyboard }
        if text.contains("trackpad") { return .trackpad }
        if text.contains("headphone") || text.contains("headset") || text.contains("airpods") || text.contains("beats") { return .headphones }
        if text.contains("game") || text.contains("controller") { return .gameController }
        return .other
    }
}
