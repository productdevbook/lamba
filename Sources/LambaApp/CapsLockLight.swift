import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem

/// The green Caps Lock light, blinked for notifications along with the MagSafe LED.
///
/// The light follows the Caps Lock state, so blinking means toggling Caps Lock itself
/// (`IOHIDSetModifierLockState`). To never turn typing into capitals, it only blinks when no key
/// was pressed for a couple of seconds, stops as soon as one is, and always ends in the state it
/// found.
final class CapsLockLight {
    static let shared = CapsLockLight()

    private var connect: io_connect_t = 0
    private var original: Bool?
    private var steps: [Bool] = []
    private var timer: Timer?

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) != KERN_SUCCESS { connect = 0 }
    }

    func flash(times: Int) {
        guard connect != 0, original != nil || secondsSinceTyping() > 2 else { return }
        guard let state = original ?? state() else { return }
        original = state
        // Blink away from the current state and back, `times` times.
        steps = Array(repeating: [!state, state], count: max(1, min(times, 20))).flatMap { $0 }
        timer?.invalidate()
        advance()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.advance() }
    }

    private func advance() {
        // A key pressed during the blink: stop right away and put Caps Lock back.
        guard !steps.isEmpty, secondsSinceTyping() > 0.3 else { return finish() }
        set(steps.removeFirst())
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        if let original { set(original) }
        original = nil
        steps = []
    }

    private func state() -> Bool? {
        var on = false
        return IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on) == KERN_SUCCESS ? on : nil
    }

    private func set(_ on: Bool) {
        _ = IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }

    private func secondsSinceTyping() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }
}
