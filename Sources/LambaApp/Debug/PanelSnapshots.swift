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
        for dark in [false, true] {
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
