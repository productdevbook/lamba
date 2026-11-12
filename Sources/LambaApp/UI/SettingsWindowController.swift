import AppKit
import SwiftUI

/// Which Settings page is showing; lets the window switch pages without rebuilding its content.
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsView.Tab = .general
}

/// Owns the single Settings window. The app is a menu bar accessory, so it must activate itself.
final class SettingsWindowController {
    private var window: NSWindow?
    private let router = SettingsRouter()
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Shows the window; passing a tab switches to it.
    func show(tab: SettingsView.Tab? = nil) {
        if let tab { router.tab = tab }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.settingsTitle
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.contentView = NSHostingView(rootView: SettingsView(model: model, router: router))
            window.contentMinSize = NSSize(width: 780, height: 520)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("LambaSettings")
            if !window.setFrameUsingName("LambaSettings") { window.center() }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
