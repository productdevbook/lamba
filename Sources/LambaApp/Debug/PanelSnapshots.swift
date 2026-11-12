#if DEBUG
import AppKit
import LambaCore
import SwiftUI

/// Debug-only: renders the panel and settings to PNGs for design review.
/// Run: `.build/debug/LambaApp --snapshot <directory>`
@MainActor
enum PanelSnapshots {
    private struct NullWriter: LightWriter {
        func write(_ state: LightState) throws {}
    }

    static func render(to directory: String) {
        Preferences.registerDefaults()
        RecentDownloads.shared.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        save(DownloadsPopover(downloads: .shared).environment(\.colorScheme, .dark), dark: true, to: "\(directory)/downloads-popover.png")
        ClipboardHistory.shared.start()
        SystemStatus.shared.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        save(SystemStatusPopover(status: .shared).environment(\.colorScheme, .dark), dark: true, to: "\(directory)/system-popover.png")
        save(ClipboardPopover(history: .shared).environment(\.colorScheme, .dark), dark: true, to: "\(directory)/clipboard-popover.png")
        for dark in [false, true] {
            save(HStack(spacing: 4) { SystemStatusTile(); ClipboardTile() }.padding(8), dark: dark, to: "\(directory)/tools-tile-\(dark ? "dark" : "light").png")
            save(HStack(spacing: 4) { DownloadsTile(); TrashChip() }.padding(8), dark: dark, to: "\(directory)/downloads-tile-\(dark ? "dark" : "light").png")
            let suffix = dark ? "dark" : "light"
            let idle = makeModel { light, _ in light.set(.solid(.green)) }
            save(PanelView(model: idle), dark: dark, to: "\(directory)/panel-idle-\(suffix).png")
            let running = makeModel { _, pomodoro in pomodoro.start() }
            save(PanelView(model: running), dark: dark, to: "\(directory)/panel-pomodoro-\(suffix).png")
            for step in [OnboardingView.Step.welcome, .done, .unsupported] {
                save(OnboardingView(step: step, install: { true }, finish: {}), dark: dark, to: "\(directory)/onboarding-\(step)-\(suffix).png")
            }
            for tab in SettingsView.Tab.allCases {
                save(SettingsView(model: idle, tab: tab).frame(width: 900, height: 640), dark: dark, to: "\(directory)/settings-\(tab)-\(suffix).png")
            }
        }
    }

    private static func makeModel(_ setUp: (LightController, PomodoroController) -> Void) -> AppModel {
        let light = LightController(writer: NullWriter())
        let pomodoro = PomodoroController(light: light)
        setUp(light, pomodoro)
        let activity = ActivityTracker(store: ActivityStore(url: sampleActivity()))
        let agents = AgentMonitor()
        let router = RequestRouter(light: light, pomodoro: pomodoro, activity: activity, agents: agents)
        return AppModel(light: light, pomodoro: pomodoro, router: router, installer: HelperInstaller(), power: PowerMonitor(), activity: activity, agents: agents)
    }

    /// Two weeks of plausible activity in a temp file, so statistics render with data.
    private static func sampleActivity() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lamba-sample-activity.jsonl")
        try? FileManager.default.removeItem(at: url)
        let store = ActivityStore(url: url)
        let today = Calendar.current.startOfDay(for: Date())
        let sessionsPerDay = [3, 5, 0, 4, 6, 2, 0, 4, 7, 5, 3, 6, 4, 2]
        for (offset, sessions) in sessionsPerDay.enumerated() {
            let day = today.addingTimeInterval(Double(offset - sessionsPerDay.count + 1) * 86_400)
            for index in 0..<sessions {
                let start = day.addingTimeInterval(9 * 3600 + Double(index) * 1800)
                store.append(ActivityRecord(kind: .focus, start: start, end: start.addingTimeInterval(1500), value: ActivityRecord.completed))
            }
            store.append(ActivityRecord(kind: .light, start: day.addingTimeInterval(8 * 3600), end: day.addingTimeInterval(12 * 3600), value: "orange"))
            store.append(ActivityRecord(kind: .light, start: day.addingTimeInterval(12 * 3600), end: day.addingTimeInterval(14 * 3600), value: "green"))
            store.append(ActivityRecord(kind: .light, start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(20 * 3600), value: "system"))
            store.append(ActivityRecord(kind: .charge, start: day.addingTimeInterval(8 * 3600), end: day.addingTimeInterval(10 * 3600), value: "charging"))
            store.append(ActivityRecord(kind: .charge, start: day.addingTimeInterval(10 * 3600), end: day.addingTimeInterval(18 * 3600), value: "plugged"))
            store.append(ActivityRecord(kind: .charge, start: day.addingTimeInterval(18 * 3600), end: day.addingTimeInterval(21 * 3600), value: "battery"))
            for _ in 0..<(offset % 3) {
                store.append(ActivityRecord(kind: .flash, start: day.addingTimeInterval(15 * 3600), end: day.addingTimeInterval(15 * 3600), value: "green"))
            }
        }
        return url
    }

    /// Opens Settings in an off-screen window, clicks each sidebar row with synthetic events sent
    /// to that window only, and prints which page the router ends up on.
    static func clickSidebar(to directory: String) {
        // Sanity check: does a synthetic click reach a plain SwiftUI button in such a window?
        final class Flag { var hit = false }
        let flag = Flag()
        let probe = NSWindow(contentRect: NSRect(x: -4000, y: 200, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        probe.contentView = NSHostingView(rootView: Button("Probe") { flag.hit = true }.buttonStyle(.plain).frame(width: 200, height: 100))
        probe.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            probe.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 50), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: probe.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        print("probe button hit: \(flag.hit)")
        probe.close()

        let model = makeModel { _, _ in }
        let router = SettingsRouter()
        let window = NSWindow(contentRect: NSRect(x: -4000, y: 200, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: SettingsView(model: model, router: router))
        window.orderFrontRegardless()
        window.makeKey()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let height = window.contentView!.bounds.height
        for (index, y) in stride(from: 52.0, through: 52 + 4 * 30, by: 30).enumerated() {
            let point = NSPoint(x: 90, y: height - y)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            window.sendEvent(event(.leftMouseDown))
            window.sendEvent(event(.leftMouseUp))
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            print("row \(index) at y=\(y): router.tab = \(router.tab)")
        }
        router.tab = .dock
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        window.contentView!.needsDisplay = true
        window.displayIfNeeded()
        let hosting = window.contentView!
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory + "/settings-click.png"))
        }
    }

    /// Draws through AppKit (not ImageRenderer) so native controls render too.
    private static func save<V: View>(_ view: V, dark: Bool, to path: String) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print(path)
    }
}
#endif
