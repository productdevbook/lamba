import AppKit
import SwiftUI

/// Statistics in a window of its own (not a Settings tab).
final class StatisticsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.statistics
            window.contentView = NSHostingView(rootView: StatisticsView(model: model))
            window.contentMinSize = NSSize(width: 620, height: 480)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("LambaStatistics")
            if !window.setFrameUsingName("LambaStatistics") { window.center() }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
