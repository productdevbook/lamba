import Foundation

/// The user's own wallpaper/appearance, saved before Lamba first changes them, so that leaving a
/// context whose look doesn't set a field puts the user's original back instead of leaving the
/// previous context's choice behind.
public struct LookBaseline: Codable, Equatable, Sendable {
    /// Display key -> wallpaper file URL string, for displays whose wallpaper Lamba has changed.
    public var wallpapers: [String: String] = [:]
    /// Whether the Mac was in dark mode before Lamba first changed the appearance.
    public var darkMode: Bool?

    public init(wallpapers: [String: String] = [:], darkMode: Bool? = nil) {
        self.wallpapers = wallpapers
        self.darkMode = darkMode
    }

    public var isEmpty: Bool { wallpapers.isEmpty && darkMode == nil }

    /// Remembers a display's original wallpaper; only the first call per display counts.
    public mutating func captureWallpaper(displayKey: String, current: String?) {
        guard wallpapers[displayKey] == nil, let current else { return }
        wallpapers[displayKey] = current
    }

    public mutating func captureAppearance(isDark: Bool) {
        if darkMode == nil { darkMode = isDark }
    }
}

/// What to do with one field of the Mac when a look is applied.
public enum FieldAction<Value: Equatable & Sendable>: Equatable, Sendable {
    case leave
    case set(Value)
    case restore(Value)
}

public enum LookPlanner {
    /// Set when the look wants it; otherwise restore the saved original (if Lamba ever changed it).
    public static func appearance(_ desired: ContextLook.Appearance?, baseline: LookBaseline) -> FieldAction<Bool> {
        if let desired { return .set(desired == .dark) }
        if let original = baseline.darkMode { return .restore(original) }
        return .leave
    }

    public static func wallpaper(_ desired: String?, displayKey: String, baseline: LookBaseline) -> FieldAction<String> {
        if let desired { return .set(desired) }
        if let original = baseline.wallpapers[displayKey] { return .restore(original) }
        return .leave
    }
}

/// The contexts created on first run.
public enum DefaultContexts {
    public struct Names: Sendable {
        public var work: String, personal: String, presenting: String
        public init(work: String, personal: String, presenting: String) {
            self.work = work; self.personal = personal; self.presenting = presenting
        }
    }

    /// Work (Mon-Fri 09:00-18:00), Personal (the fallback) and Presenting (when mirroring).
    /// Looks change nothing except tinting the Dock, so first launch never touches the Mac.
    public static func make(names: Names, appPaths: [String]) -> (contexts: [DockContext], defaultID: UUID) {
        let work = DockContext(
            name: names.work, color: .blue, appPaths: appPaths,
            rules: [ContextRule(trigger: .schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60))])
        let personal = DockContext(name: names.personal, color: .pink, appPaths: appPaths)
        let presenting = DockContext(name: names.presenting, color: .green, appPaths: appPaths, rules: [ContextRule(trigger: .mirroring)])
        return ([work, personal, presenting], personal.id)
    }
}
