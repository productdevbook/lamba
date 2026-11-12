import AppKit
import Combine
import SwiftUI

/// Shows the Lamba Dock at the bottom of the main screen and keeps the system Dock out of the way.
///
/// The window spans the screen width and is taller than the bar to leave room for magnification.
/// It only takes mouse events while the pointer is over the bar, so the rest stays click-through.
final class DockWindowController {
    private let model: AppModel
    private let dock = DockModel()
    private let layout = DockLayout()
    private let meetings = MeetingMonitor()
    private let nowPlaying = NowPlayingMonitor()
    private let shelf = ShelfModel()
    private let toggles = QuickToggles()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        meetings.onStartingSoon = { [weak model] in model?.flash(.orange, times: 3) }
        // Settings may have been left applied by a crash; put the system Dock back first.
        if !Preferences.dockEnabled || !Preferences.hideAppleDock { AppleDock.restore() }
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleApply() })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.position() })
        apply()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func reimportApps() {
        dock.reimportFromAppleDock()
    }

    /// Restores the system Dock; called when Lamba quits.
    func tearDown() {
        hide()
        AppleDock.restore()
    }

    // MARK: Preferences

    private var applyScheduled = false

    /// Defaults change notifications can arrive synchronously, even in the middle of SwiftUI
    /// layout (which can itself touch defaults), so changes are applied on the next run loop pass.
    private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyScheduled = false
            self?.apply()
        }
    }

    private func apply() {
        let style = DockStyle(rawValue: Preferences.dockStyle) ?? .strip
        if layout.style != style { layout.style = style }
        let size = CGFloat(Preferences.dockIconSize)
        let magnification = CGFloat(Preferences.dockMagnification)
        if layout.iconSize != size { layout.iconSize = size }
        if layout.magnification != magnification { layout.magnification = magnification }

        if Preferences.dockEnabled {
            show()
            style == .classic ? meetings.stop() : meetings.start()
            Preferences.hideAppleDock ? AppleDock.hide() : AppleDock.restore()
        } else {
            hide()
            meetings.stop()
            AppleDock.restore()
        }
        position()
    }

    // MARK: Window

    private func show() {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        self.panel = panel
        DockPopover.shared.dockWindow = panel
        panel.contentView = FirstMouseHostingView(rootView: DockRootView(dock: dock, layout: layout, model: model, contexts: model.contexts, shelf: shelf, toggles: toggles, meetings: meetings, nowPlaying: nowPlaying))
        position()
        panel.orderFrontRegardless()

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.trackPointer() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.trackPointer()
            return event
        }) {
            monitors.append(local)
        }
        // The pointer can leave without a move event reaching us (e.g. a menu opened).
        Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.trackPointer() }
            .store(in: &cancellables)
        // Running apps changing resizes the bar.
        dock.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.trackPointer() }
            .store(in: &cancellables)
    }

    private func hide() {
        DockPopover.shared.close()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        cancellables = []
        panel?.orderOut(nil)
        panel = nil
    }

    private func position() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: layout.windowHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if layout.width != frame.width { layout.width = frame.width }
    }

    /// Enables mouse events over the bar (and the magnified area above it while hovering).
    private func trackPointer() {
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        let local = NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        var area = layout.barFrame
        if layout.style == .classic {
            // Slack for magnified growth, and the label space above while hovering.
            area = area.insetBy(dx: -layout.iconSize, dy: 0)
            if layout.pointerX != nil { area.size.height = panel.frame.height - area.minY }
        }
        let isInside = area.contains(local)

        panel.ignoresMouseEvents = !isInside
        let pointerX: CGFloat? = isInside ? local.x : nil
        if layout.pointerX != pointerX { layout.pointerX = pointerX }
    }
}

/// Lets the first click on a Dock icon act immediately, without first focusing the panel.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
