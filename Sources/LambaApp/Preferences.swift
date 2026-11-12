import Foundation
import LambaCore

/// User preferences, stored in UserDefaults. SwiftUI reads the same keys through `@AppStorage`.
enum Preferences {
    enum Key {
        static let playSounds = "playSounds"
        static let flashOnPhaseChange = "flashOnPhaseChange"
        static let longBreakMinutes = "longBreakMinutes"
        static let sessionsBeforeLongBreak = "sessionsBeforeLongBreak"
        static let defaultPresetID = "defaultPresetID"
        static let onboardingCompleted = "onboardingCompleted"
        static let haptics = "haptics"
        static let hapticWaveform = "hapticWaveform"
        static let hapticIntensity = "hapticIntensity"
        static let hapticPulses = "hapticPulses"
        static let dockEnabled = "dockEnabled"
        static let dockStyle = "dockStyle"
        static let hideAppleDock = "hideAppleDock"
        static let dockIconSize = "dockIconSize"
        static let dockMagnification = "dockMagnification"
        static let dockPinnedPaths = "dockPinnedPaths"
        static let dockDownloads = "dockDownloads"
        static let dockClipboard = "dockClipboard"
        static let dockSystemStatus = "dockSystemStatus"
        static let keyboardFlash = "keyboardFlash"
        static let capsLockFlash = "capsLockFlash"
        static let keyboardMoods = "keyboardMoods"
        static let keyboardOffAfter = "keyboardOffAfter"
        static let keyboardNightDim = "keyboardNightDim"
        static let keyboardNightStart = "keyboardNightStart"
        static let keyboardNightEnd = "keyboardNightEnd"
        static let keyboardBrightness = "keyboardBrightness"
    }

    private static var store: UserDefaults { .standard }

    /// Call once at launch so `@AppStorage` and these accessors share the same defaults.
    static func registerDefaults() {
        store.register(defaults: [
            Key.playSounds: true,
            Key.flashOnPhaseChange: true,
            Key.longBreakMinutes: 15.0,
            Key.sessionsBeforeLongBreak: 4,
            Key.defaultPresetID: PomodoroPreset.default.id,
            Key.onboardingCompleted: false,
            Key.haptics: true,
            Key.hapticWaveform: HapticStyle.default.waveform,
            Key.hapticIntensity: HapticStyle.default.intensity,
            Key.hapticPulses: HapticStyle.default.pulses,
            Key.dockEnabled: false,
            Key.dockStyle: DockStyle.strip.rawValue,
            Key.hideAppleDock: true,
            Key.dockIconSize: 48.0,
            Key.dockMagnification: 1.6,
            Key.dockDownloads: true,
            Key.dockClipboard: true,
            Key.dockSystemStatus: true,
            Key.keyboardFlash: true,
            Key.capsLockFlash: true,
            Key.keyboardMoods: true,
            Key.keyboardOffAfter: true,
            Key.keyboardNightDim: true,
            Key.keyboardNightStart: 20,
            Key.keyboardNightEnd: 8,
            Key.keyboardBrightness: 0.5,
        ])
    }

    static var playSounds: Bool { store.bool(forKey: Key.playSounds) }
    static var flashOnPhaseChange: Bool { store.bool(forKey: Key.flashOnPhaseChange) }
    static var haptics: Bool { store.bool(forKey: Key.haptics) }
    static var keyboardFlash: Bool { store.bool(forKey: Key.keyboardFlash) }
    static var capsLockFlash: Bool { store.bool(forKey: Key.capsLockFlash) }
    static var keyboardMoods: Bool { store.bool(forKey: Key.keyboardMoods) }
    static var keyboardOffAfter: Bool { store.bool(forKey: Key.keyboardOffAfter) }
    static var keyboardNightDim: Bool { store.bool(forKey: Key.keyboardNightDim) }

    /// Brightest level of keyboard flashes by day (0...1).
    static var keyboardBrightness: Float { Float(store.double(forKey: Key.keyboardBrightness)) }

    /// Between the night start and end hours (local time); an end before the start spans midnight.
    static var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = store.integer(forKey: Key.keyboardNightStart), end = store.integer(forKey: Key.keyboardNightEnd)
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    static var hapticStyle: HapticStyle {
        HapticStyle(
            waveform: store.integer(forKey: Key.hapticWaveform),
            intensity: store.double(forKey: Key.hapticIntensity),
            pulses: store.integer(forKey: Key.hapticPulses)
        )
    }

    static func resetHapticStyle() {
        [Key.hapticWaveform, Key.hapticIntensity, Key.hapticPulses].forEach(store.removeObject)
    }
    static var dockEnabled: Bool { store.bool(forKey: Key.dockEnabled) }
    static var dockStyle: String { store.string(forKey: Key.dockStyle) ?? DockStyle.strip.rawValue }
    static var hideAppleDock: Bool { store.bool(forKey: Key.hideAppleDock) }
    static var dockIconSize: Double { store.double(forKey: Key.dockIconSize) }
    static var dockMagnification: Double { store.double(forKey: Key.dockMagnification) }

    /// `nil` until the user changes the Dock; then the apps are imported from the system Dock.
    static var dockPinnedPaths: [String]? {
        get { store.stringArray(forKey: Key.dockPinnedPaths) }
        set { store.set(newValue, forKey: Key.dockPinnedPaths) }
    }

    static var longBreakMinutes: Double { store.double(forKey: Key.longBreakMinutes) }
    static var sessionsBeforeLongBreak: Int { store.integer(forKey: Key.sessionsBeforeLongBreak) }

    static var onboardingCompleted: Bool {
        get { store.bool(forKey: Key.onboardingCompleted) }
        set { store.set(newValue, forKey: Key.onboardingCompleted) }
    }

    static var defaultPreset: PomodoroPreset {
        let id = store.string(forKey: Key.defaultPresetID)
        return PomodoroPreset.all.first { $0.id == id } ?? .default
    }

    /// A preset's work/break lengths combined with the user's long-break settings.
    static func settings(for preset: PomodoroPreset) -> PomodoroSettings {
        var settings = preset.settings
        settings.longBreakMinutes = longBreakMinutes
        settings.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
        return settings
    }
}
