import AppKit

enum Alerts {
    static func show(_ message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    /// Asks for confirmation; returns true when the user picks `action`.
    static func confirm(_ message: String, detail: String, action: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: action).hasDestructiveAction = true
        alert.addButton(withTitle: L10n.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
