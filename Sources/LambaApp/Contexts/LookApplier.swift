import AppKit
import LambaCore

/// Makes the Mac match a context's look. Before it first changes the wallpaper or appearance it
/// saves the user's own (the baseline, persisted), and when a look leaves a field alone after
/// Lamba changed it, the baseline is put back.
final class LookApplier {
    private static let baselineKey = "dockLookBaseline"

    private let defaults: UserDefaults
    var flash: (LightState, Int) -> Void = { _, _ in }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private(set) var baseline: LookBaseline {
        get {
            defaults.data(forKey: Self.baselineKey).flatMap { try? JSONDecoder().decode(LookBaseline.self, from: $0) } ?? LookBaseline()
        }
        set {
            defaults.set(newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue), forKey: Self.baselineKey)
        }
    }

    func apply(_ look: ContextLook) {
        applyWallpaper(look.wallpaper)
        applyAppearance(look.appearance)
        if let color = look.flashColor, color != .system { flash(color, 2) }
        if let shortcut = look.shortcut, !shortcut.isEmpty { ShortcutsRunner.run(shortcut) }
        open(look.openApps)
        hide(look.hideApps)
    }

    // MARK: - Wallpaper

    /// Stable per-display key (the display ID), so a baseline survives reordering of screens.
    private func key(for screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    private func applyWallpaper(_ reference: String?) {
        var baseline = self.baseline
        let before = baseline
        for screen in NSScreen.screens {
            guard let displayKey = key(for: screen) else { continue }
            switch LookPlanner.wallpaper(reference, displayKey: displayKey, baseline: baseline) {
            case .leave:
                break
            case let .set(value):
                guard let url = fileURL(for: value) else { continue }
                baseline.captureWallpaper(displayKey: displayKey, current: NSWorkspace.shared.desktopImageURL(for: screen)?.absoluteString)
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            case let .restore(original):
                if let url = URL(string: original), FileManager.default.fileExists(atPath: url.path) {
                    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                }
                baseline.wallpapers[displayKey] = nil
            }
        }
        if baseline != before { self.baseline = baseline }
    }

    private func fileURL(for reference: String) -> URL? {
        if let builtin = BuiltinWallpaper(reference: reference) { return builtin.fileURL() }
        let url = URL(fileURLWithPath: reference)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Appearance

    private func applyAppearance(_ appearance: ContextLook.Appearance?) {
        var baseline = self.baseline
        switch LookPlanner.appearance(appearance, baseline: baseline) {
        case .leave:
            return
        case let .set(dark):
            baseline.captureAppearance(isDark: SystemAppearance.isDark)
            SystemAppearance.setDark(dark)
        case let .restore(dark):
            SystemAppearance.setDark(dark)
            baseline.darkMode = nil
        }
        self.baseline = baseline
    }

    // MARK: - Apps

    /// Launches without taking focus from what the user is doing.
    private func open(_ paths: [String]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        for path in paths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        }
    }

    private func hide(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let targets = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        for app in NSWorkspace.shared.runningApplications {
            if let path = app.bundleURL?.standardizedFileURL.path, targets.contains(path) { app.hide() }
        }
    }
}
