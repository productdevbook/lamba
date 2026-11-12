import Foundation
import IOKit.ps
import LambaCore

/// Tracks the charger state through IOKit power source notifications.
final class PowerMonitor {
    private(set) var state: ChargeState
    var onChange: (() -> Void)?
    private var source: CFRunLoopSource?

    init() {
        state = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func update() {
        let new = Self.read()
        guard new != state else { return }
        state = new
        onChange?()
    }

    static func read() -> ChargeState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .notCharging }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        guard providing == kIOPMACPowerKey else { return .onBattery }

        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return (description[kIOPSIsChargingKey] as? Bool) == true ? .charging : .notCharging
        }
        return .notCharging
    }
}
