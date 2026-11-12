import AppKit
import LambaCore
import SwiftUI

/// Menu bar item: an icon that mirrors the LED color and the Pomodoro countdown.
/// Left click opens the panel; right click (or control-click) opens a short context menu.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()

        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        refresh()
    }

    func refresh() {
        model.refresh()
        guard let button = item.button else { return }
        updateIcon()
        if let snapshot = model.pomodoro {
            button.title = " " + snapshot.formattedRemaining
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            button.title = ""
        }
    }

    // MARK: Icon

    private var shownLight: LightState?
    private var blinkTimer: Timer?
    private var blinkVisible = true

    /// Mirrors the LED: colored bolt when lit, hollow bolt when dark, blinking for hardware blink modes.
    private func updateIcon() {
        let light = model.visibleLight
        guard light != shownLight else { return }
        shownLight = light
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkVisible = true

        if let interval = StatusIcon.blinkInterval(for: light) {
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.blinkVisible.toggle()
                self.item.button?.image = StatusIcon.image(for: self.blinkVisible ? light : .off)
            }
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        }
        item.button?.image = StatusIcon.image(for: light)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return togglePopover() }
        let isSecondaryClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        isSecondaryClick ? showContextMenu() : togglePopover()
    }

    private func showContextMenu() {
        closePopover()
        model.refresh()
        let menu = NSMenu()

        if model.pomodoro == nil {
            menu.addItem(MenuAction(L10n.pomodoroStartMenu) { [model] in model.startPomodoro() })
        } else {
            menu.addItem(MenuAction(L10n.pomodoroStop) { [model] in model.stopPomodoro() })
        }
        if model.mode != .solid(.system) || model.pomodoro != nil {
            menu.addItem(MenuAction(L10n.resetLight) { [model] in model.select(.solid(.system)) })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction(L10n.statistics + "…") { [model] in model.openStatistics() })
        menu.addItem(MenuAction(L10n.settings + "…", key: ",") { [model] in model.openSettings() })
        if Updater.isConfigured {
            menu.addItem(MenuAction(L10n.checkForUpdates) { Updater.shared.checkForUpdates() })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction(L10n.quit, key: "q") { [model] in model.quit() })

        // Attaching the menu only for this click keeps left click free for the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Menu item that runs a closure.
private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

/// Draws the menu bar glyph in the LED's current color.
enum StatusIcon {
    static let green = NSColor(red: 0.24, green: 0.86, blue: 0.45, alpha: 1)
    static let orange = NSColor(red: 1.00, green: 0.62, blue: 0.10, alpha: 1)

    /// Half-period of the hardware blink modes, matching the panel preview.
    static func blinkInterval(for state: LightState) -> TimeInterval? {
        switch state {
        case .orangeBlinkSlow: return 1.0
        case .orangeBlinkFast: return 0.25
        default: return nil
        }
    }

    static func image(for state: LightState) -> NSImage {
        let color: NSColor?
        switch state {
        case .green: color = green
        case .orange, .orangeBlinkSlow, .orangeBlinkFast: color = orange
        case .off, .system: color = nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        guard let color else {
            // Dark LED: hollow bolt that follows the menu bar's light/dark appearance.
            let image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Lamba")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            return image ?? NSImage()
        }
        let colored = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Lamba")?.withSymbolConfiguration(colored)
        image?.isTemplate = false
        return image ?? NSImage()
    }
}
