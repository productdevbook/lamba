import Foundation

/// The keyboard backlight, used as a second notification light next to the MagSafe LED.
///
/// macOS has no public API for it; this uses CoreBrightness's `KeyboardBrightnessClient` (what
/// Control Center's keyboard brightness uses), looked up at runtime. If the class or a method is
/// missing (another macOS, a Mac without a backlit keyboard), it does nothing.
final class KeyboardLight {
    static let shared = KeyboardLight()

    /// A steady effect besides notification flashes.
    enum Mood: Equatable {
        /// The user's own brightness (and auto-brightness).
        case normal
        /// Pomodoro focus: dimmed, less distracting.
        case focus
        /// Pomodoro break: slow breathing.
        case rest
        /// Claude needs you: a short glow every two seconds until answered.
        case attention
    }

    var mood: Mood = .normal {
        didSet { if mood != oldValue { moodChanged() } }
    }

    private let client: NSObject?
    private let keyboardID: UInt64
    private var flashSteps: [Float] = []
    private var flashTimer: Timer?
    private var moodTimer: Timer?
    private var moodStarted = Date()
    /// The user's brightness and auto-brightness while Lamba drives the light; put back after.
    private var base: (level: Float, auto: Bool?)?

    private init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil
            keyboardID = 0
            return
        }
        let client = type.init()
        self.client = client
        var id: UInt64 = 1
        let copyIDs = NSSelectorFromString("copyKeyboardBacklightIDs")
        if client.responds(to: copyIDs), let ids = client.perform(copyIDs)?.takeRetainedValue() as? [NSNumber], let first = ids.first {
            id = first.uint64Value
        }
        keyboardID = id
    }

    var isAvailable: Bool { brightness() != nil }

    /// Blinks the backlight like the LED's notification flash (0.25 s on, 0.25 s off), then
    /// returns to the mood (or the user's brightness).
    func flash(times: Int) {
        guard takeOver() else { return }
        flashSteps = Array(repeating: [Float(1), Float(0)], count: max(1, min(times, 20))).flatMap { $0 }
        flashTimer?.invalidate()
        advanceFlash()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.advanceFlash() }
    }

    private func advanceFlash() {
        guard !flashSteps.isEmpty else {
            flashTimer?.invalidate()
            flashTimer = nil
            return mood == .normal ? release() : applyMood()
        }
        setBrightness(flashSteps.removeFirst())
    }

    private func moodChanged() {
        moodTimer?.invalidate()
        moodTimer = nil
        guard mood != .normal else {
            if flashSteps.isEmpty { release() }
            return
        }
        guard takeOver() else { return }
        moodStarted = Date()
        applyMood()
        if mood == .rest || mood == .attention {
            moodTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.applyMood() }
        }
    }

    private func applyMood() {
        guard flashSteps.isEmpty, let base else { return }
        let t = Date().timeIntervalSince(moodStarted)
        switch mood {
        case .normal:
            return
        case .focus:
            setBrightness(base.level * 0.35)
        case .rest:
            // One slow breath every 5 s.
            let phase = (1 - cos(t * 2 * .pi / 5)) / 2
            setBrightness(Float(0.04 + 0.5 * phase))
        case .attention:
            // A quick glow at the start of every 2 s, else the user's level dimmed.
            let x = t.truncatingRemainder(dividingBy: 2)
            let glow = x < 0.6 ? sin(x / 0.6 * .pi) : 0
            setBrightness(max(base.level * 0.35, Float(glow)))
        }
    }

    /// Remembers the user's settings the first time Lamba changes the light.
    private func takeOver() -> Bool {
        if base != nil { return true }
        guard let level = brightness() else { return false }
        base = (level, autoBrightness())
        setAutoBrightness(false)
        return true
    }

    private func release() {
        guard let base else { return }
        setBrightness(base.level)
        if let auto = base.auto { setAutoBrightness(auto) }
        self.base = nil
    }

    // MARK: Private API calls (Objective-C methods with scalar arguments)

    private func brightness() -> Float? {
        typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
        guard let (client, imp, selector) = method("brightnessForKeyboard:") else { return nil }
        return unsafeBitCast(imp, to: Get.self)(client, selector, keyboardID)
    }

    private func setBrightness(_ level: Float) {
        typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        guard let (client, imp, selector) = method("setBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(imp, to: Set.self)(client, selector, level, keyboardID)
    }

    private func autoBrightness() -> Bool? {
        typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Bool
        guard let (client, imp, selector) = method("isAutoBrightnessEnabledForKeyboard:") else { return nil }
        return unsafeBitCast(imp, to: Get.self)(client, selector, keyboardID)
    }

    /// Auto-brightness would otherwise fight the flash.
    private func setAutoBrightness(_ enabled: Bool) {
        typealias Set = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        guard let (client, imp, selector) = method("enableAutoBrightness:forKeyboard:") else { return }
        _ = unsafeBitCast(imp, to: Set.self)(client, selector, enabled, keyboardID)
    }

    private func method(_ name: String) -> (NSObject, IMP, Selector)? {
        let selector = NSSelectorFromString(name)
        guard let client, client.responds(to: selector) else { return nil }
        return (client, client.method(for: selector), selector)
    }
}
