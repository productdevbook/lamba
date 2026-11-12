import Foundation

/// Reads from and temporarily adjusts the system Dock (`com.apple.dock` preferences).
///
/// Hiding uses the Dock's own auto-hide with a very long reveal delay, so it is fully reversible.
/// The user's previous values are saved first and written back by `restore()`.
enum AppleDock {
    private static let domain = "com.apple.dock" as CFString
    private static let savedKey = "appleDockSavedSettings"
    private static let neverRevealDelay = 1000.0

    static let finderPath = "/System/Library/CoreServices/Finder.app"

    /// Apps pinned in the system Dock, in order (Finder first, as in the Dock).
    static func pinnedAppPaths() -> [String] {
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        let paths = tiles.compactMap { tile -> String? in
            let fileData = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
            return (fileData?["_CFURLString"] as? String).flatMap { URL(string: $0)?.path }
        }
        return [finderPath] + paths.filter { $0 != finderPath && FileManager.default.fileExists(atPath: $0) }
    }

    static var isHiddenByLamba: Bool {
        UserDefaults.standard.dictionary(forKey: savedKey) != nil
    }

    static func hide() {
        guard !isHiddenByLamba else { return }
        var saved: [String: Any] = [:]
        if let autohide = CFPreferencesCopyAppValue("autohide" as CFString, domain) { saved["autohide"] = autohide }
        if let delay = CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) { saved["autohide-delay"] = delay }
        UserDefaults.standard.set(saved, forKey: savedKey)

        CFPreferencesSetAppValue("autohide" as CFString, kCFBooleanTrue, domain)
        CFPreferencesSetAppValue("autohide-delay" as CFString, neverRevealDelay as CFNumber, domain)
        apply()
    }

    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedKey) else { return }
        CFPreferencesSetAppValue("autohide" as CFString, saved["autohide"] as CFPropertyList?, domain)
        CFPreferencesSetAppValue("autohide-delay" as CFString, saved["autohide-delay"] as CFPropertyList?, domain)
        UserDefaults.standard.removeObject(forKey: savedKey)
        apply()
    }

    /// Saves the preferences and restarts the Dock so they take effect.
    private static func apply() {
        CFPreferencesAppSynchronize(domain)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
        task.waitUntilExit()
    }
}
