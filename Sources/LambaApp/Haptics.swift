import AppKit

/// Trackpad vibration.
///
/// Prefers driving the Taptic Engine directly through the private MultitouchSupport framework,
/// which works even when no finger is on the trackpad (felt through the case). If that API is
/// missing or fails (e.g. after a macOS update), falls back to the public haptic API, which macOS
/// only plays while a finger touches the trackpad.
final class Haptics {
    static let shared = Haptics()

    static let maxPulses = 10
    private static let pulseInterval: TimeInterval = 0.12

    private let actuator = TrackpadActuator()

    /// Plays the user's haptic style; `times` overrides its pulse count.
    func pulse(times: Int? = nil, style: HapticStyle = Preferences.hapticStyle) {
        let count = min(max(times ?? style.pulses, 1), Self.maxPulses)
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * Self.pulseInterval) { [self] in
                if actuator?.actuate(waveform: Int32(style.waveform), intensity: Float(style.intensity)) != true {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
    }
}

/// How a vibration feels. Waveform and intensity map to the private actuator's parameters.
struct HapticStyle: Equatable {
    var waveform: Int
    var intensity: Double
    var pulses: Int

    /// Picked in hands-on testing as the most noticeable through the case, also with the lid closed.
    static let `default` = HapticStyle(waveform: 6, intensity: 0.5, pulses: 3)

    /// Waveform ids the actuator accepts.
    static let waveforms = [1, 2, 3, 4, 5, 6, 15, 16]
    static let intensityRange = 0.25...4.0
    static let pulseRange = 1...5
}

/// Minimal wrapper around the private `MTActuator*` functions. `nil` when unavailable.
private final class TrackpadActuator {
    private typealias CreateDefault = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias GetDeviceID = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias CreateActuator = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias Open = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias Actuate = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt32, Float, Float) -> Int32

    private let createDefault: CreateDefault
    private let getDeviceID: GetDeviceID
    private let createActuator: CreateActuator
    private let open: Open
    private let actuateFunction: Actuate
    private var actuator: UnsafeMutableRawPointer?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createDefault = dlsym(handle, "MTDeviceCreateDefault"),
              let getDeviceID = dlsym(handle, "MTDeviceGetDeviceID"),
              let createActuator = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let open = dlsym(handle, "MTActuatorOpen"),
              let actuate = dlsym(handle, "MTActuatorActuate") else { return nil }
        self.createDefault = unsafeBitCast(createDefault, to: CreateDefault.self)
        self.getDeviceID = unsafeBitCast(getDeviceID, to: GetDeviceID.self)
        self.createActuator = unsafeBitCast(createActuator, to: CreateActuator.self)
        self.open = unsafeBitCast(open, to: Open.self)
        self.actuateFunction = unsafeBitCast(actuate, to: Actuate.self)
    }

    /// Returns false if the trackpad could not be driven; the caller then falls back.
    func actuate(waveform: Int32, intensity: Float) -> Bool {
        if let actuator, actuateFunction(actuator, waveform, 0, 0, intensity) == 0 { return true }
        // The device can change (sleep, external trackpad); reopen once and retry.
        actuator = openActuator()
        guard let actuator else { return false }
        return actuateFunction(actuator, waveform, 0, 0, intensity) == 0
    }

    private func openActuator() -> UnsafeMutableRawPointer? {
        var deviceID: UInt64 = 0
        guard let device = createDefault(), getDeviceID(device, &deviceID) == 0,
              let actuator = createActuator(deviceID), open(actuator) == 0 else { return nil }
        return actuator
    }
}
