import AppKit
import SwiftUI

/// A small floating panel above a Dock item (session list, battery details).
///
/// SwiftUI's `.popover` doesn't work from the Dock's non-activating panel while Lamba is in the
/// background, so this is a borderless panel of its own. It closes on a second click of its
/// item, a click anywhere else, or Escape.
final class DockPopover {
    static let shared = DockPopover()

    /// The Dock window, to convert item frames to screen coordinates.
    weak var dockWindow: NSWindow?

    private var panel: NSPanel?
    private var shownID: String?
    private var monitors: [Any] = []

    var isShown: Bool { panel != nil }

    /// `anchor` is the item's frame in the Dock window's SwiftUI global space (origin top-left).
    func toggle<Content: View>(id: String, anchor: CGRect, @ViewBuilder content: () -> Content) {
        if shownID == id { return close() }
        close()
        guard let dockWindow, let contentView = dockWindow.contentView else { return }

        let hosting = FirstMouseHostingView(rootView: PopoverChrome(content: content()))
        let size = hosting.fittingSize
        let anchorTop = dockWindow.frame.minY + contentView.bounds.height - anchor.minY
        var origin = NSPoint(x: dockWindow.frame.minX + anchor.midX - size.width / 2, y: anchorTop + 8)
        if let screen = dockWindow.screen {
            origin.x = min(max(origin.x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        }

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: dockWindow.level.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        shownID = id

        // A click outside both the popover and the Dock closes it.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 { self?.close() } // Escape
            return event
        }) {
            monitors.append(monitor)
        }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        shownID = nil
    }
}

/// Rounded, blurred background shared by Dock popovers.
private struct PopoverChrome<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

/// Reports a view's frame in the Dock window (SwiftUI global space) for anchoring popovers.
struct AnchorReader: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { frame = $0 }
        })
    }
}
