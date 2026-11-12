import Foundation

/// Lamba's bundle id was `app.lamba.Lamba` before it became `dev.hamur.lamba`. On first launch
/// under the new id, copies the old settings (contexts, shelf, Dock, Pomodoro, …) across once.
enum LegacyDefaults {
    private static let oldDomain = "app.lamba.Lamba"
    private static let doneKey = "migratedFromAppLambaLamba"

    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard Bundle.main.bundleIdentifier != oldDomain,
              let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
