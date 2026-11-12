import AppKit
import LambaCore

struct PomodoroPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let settings: PomodoroSettings

    static let all = [
        PomodoroPreset(id: "short", title: "15 / 3", settings: PomodoroSettings(workMinutes: 15, shortBreakMinutes: 3, longBreakMinutes: 10)),
        PomodoroPreset(id: "classic", title: "25 / 5", settings: PomodoroSettings()),
        PomodoroPreset(id: "deep", title: "50 / 10", settings: PomodoroSettings(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 20)),
    ]
    static let `default` = all[1]

    // Presets are identified by id alone.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct RemoteMachine: Equatable, Identifiable {
    let name: String
    let isConnected: Bool
    var id: String { name }
}

/// Observable bridge between the controllers and the SwiftUI panel.
final class AppModel: ObservableObject {
    @Published private(set) var mode: LightMode = .solid(.system)
    @Published private(set) var pomodoro: PomodoroSnapshot?
    @Published private(set) var pomodoroSettings: PomodoroSettings?
    @Published private(set) var error: String?
    /// What the LED physically shows now (`.system` resolved through the charger state).
    @Published private(set) var visibleLight: LightState = .system
    @Published private(set) var chargeState: ChargeState = .notCharging
    /// Coding-agent activity reported through hooks (`lamba agent …`).
    @Published private(set) var agent: AgentSummary?
    /// A tool call waiting for Allow/Deny in the Dock.
    @Published private(set) var permission: PermissionPrompt?
    @Published private(set) var agentSessions: [AgentSessionInfo] = []
    /// A session that just finished: the Dock briefly turns into a notification for it.
    @Published private(set) var announcement: AgentSessionInfo?
    private var announcementToken = 0
    /// SSH hosts set up for Claude Code, and whether Lamba is connected to them.
    @Published private(set) var remoteMachines: [RemoteMachine] = []
    weak var tunnels: SSHTunnels?
    /// Dock contexts (Work, Personal, …) and the active one.
    let contexts = ContextEngine()
    let isSupported = HardwareSupport.hasMagSafeLED
    var openSettings: () -> Void = {}
    var openStatistics: () -> Void = {}
    var reimportDock: () -> Void = {}

    private let light: LightController
    private let pomodoroController: PomodoroController
    private let router: RequestRouter
    private let installer: HelperInstaller
    private let power: PowerMonitor
    private let activity: ActivityTracker
    private let agents: AgentMonitor
    /// Bumped whenever new activity is recorded, so statistics views reload.
    @Published private(set) var activityRevision = 0

    init(
        light: LightController,
        pomodoro: PomodoroController,
        router: RequestRouter,
        installer: HelperInstaller,
        power: PowerMonitor,
        activity: ActivityTracker,
        agents: AgentMonitor
    ) {
        self.agents = agents
        self.power = power
        self.activity = activity
        self.light = light
        self.pomodoroController = pomodoro
        self.router = router
        self.installer = installer
        refresh()
        contexts.flash = { [weak self] color, times in self?.flash(color, times: times) }
        activity.onRecord = { [weak self] in self?.activityRevision += 1 }
    }

    func refresh() {
        mode = light.mode
        error = light.lastError
        visibleLight = light.current.resolved(for: power.state)
        chargeState = power.state
        agent = agents.summary
        permission = agents.prompt
        agentSessions = agents.sessions
        remoteMachines = tunnels?.status.map { RemoteMachine(name: $0.host, isConnected: $0.connected) } ?? []
        pomodoro = pomodoroController.snapshot
        pomodoroSettings = pomodoroController.settings
        KeyboardLight.shared.mood = keyboardMood
    }

    /// Claude waiting beats Pomodoro: focus dims the keyboard light, a break breathes.
    private var keyboardMood: KeyboardLight.Mood {
        guard Preferences.keyboardMoods else { return .normal }
        if permission != nil { return .attention }
        if case .waiting? = agent { return .attention }
        guard let pomodoro, !pomodoro.isPaused else { return .normal }
        return pomodoro.phase == .work ? .focus : .rest
    }

    /// Fraction of the current Pomodoro phase that has elapsed (0...1).
    var pomodoroProgress: Double {
        guard let pomodoro, let pomodoroSettings else { return 0 }
        let total = pomodoroSettings.duration(of: pomodoro.phase)
        return total > 0 ? 1 - Double(pomodoro.remainingSeconds) / total : 0
    }

    // MARK: Intents

    func select(_ mode: LightMode) { router.setManually(mode) }
    func startPomodoro() { pomodoroController.start(settings: Preferences.settings(for: Preferences.defaultPreset)) }
    func pausePomodoro() { pomodoroController.pause() }
    /// Brings forward the app (and tab) of a session, or of the latest one; falls back to a running terminal.
    func showAgent(_ session: AgentSessionInfo? = nil) {
        if let host = session?.host ?? permission?.host ?? agents.host, TerminalFocus.show(host) { return }
        let fallbacks = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.microsoft.VSCode"]
        let running = NSWorkspace.shared.runningApplications
        for id in fallbacks {
            if let app = running.first(where: { $0.bundleIdentifier == id }) {
                app.activate()
                return
            }
        }
    }

    static let announcementDuration: TimeInterval = 4.5

    func announce(_ session: AgentSessionInfo) {
        announcement = session
        announcementToken += 1
        let token = announcementToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.announcementDuration) { [weak self] in
            if self?.announcementToken == token { self?.announcement = nil }
        }
    }

    func dismissAnnouncement() {
        announcementToken += 1
        announcement = nil
    }

    func answerPermission(_ decision: PermissionDecision) {
        guard let permission else { return }
        agents.resolve(permission.id, decision)
    }

    /// Flashes the LED (and vibrates, if enabled), like `lamba flash`.
    func flash(_ color: LightState, times: Int) { _ = router.handle(.flash(color: color, times: times)) }
    /// Starts a session, or pauses/resumes the running one.
    func togglePomodoro() {
        guard let pomodoro else { return startPomodoro() }
        pomodoro.isPaused ? resumePomodoro() : pausePomodoro()
    }
    func resumePomodoro() { pomodoroController.resume() }
    func skipPomodoro() { pomodoroController.skip() }
    func stopPomodoro() { pomodoroController.stop() }
    func quit() { NSApp.terminate(nil) }

    func reinstallHelper() {
        do {
            try installer.install()
            light.set(light.mode) // re-apply now that the helper is back
        } catch HelperInstaller.Failure.cancelled {
        } catch {
            Alerts.show(L10n.installFailed, detail: "\(error)")
        }
    }

    // MARK: Statistics

    func report(days: Int) -> ActivityReport {
        activity.report(days: days)
    }

    func clearHistory() {
        guard Alerts.confirm(L10n.statsClearConfirm, detail: L10n.statsClearDetail, action: L10n.statsClearAction) else { return }
        activity.clearHistory()
    }

    func exportCSV(_ report: ActivityReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "lamba-\(report.days.count)d.csv"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Alerts.show(L10n.exportCSV, detail: error.localizedDescription)
        }
    }

    func copySummary(_ report: ActivityReport) {
        var lines = [
            "\(L10n.appName) · \(L10n.days(report.days.count))",
            "\(L10n.kpiFocus): \(L10n.duration(report.focusSeconds))",
            "\(L10n.kpiSessions): \(report.completedSessions)",
            "\(L10n.kpiStreak): \(L10n.streakDays(report.streakDays))",
            "\(L10n.kpiFlashes): \(report.flashes)",
        ]
        if !report.light.isEmpty {
            lines.append("\(L10n.lightUsage): " + report.light.map { "\(L10n.lightName($0.name)) \(L10n.duration($0.seconds))" }.joined(separator: ", "))
        }
        Integrations.copy(lines.joined(separator: "\n"))
    }

    /// Removes the helper and CLI, then quits. The user deletes the app itself.
    func uninstall() {
        guard Alerts.confirm(L10n.uninstallConfirm, detail: L10n.uninstallDetail, action: L10n.uninstall) else { return }
        light.restoreSystemControl()
        do {
            try installer.uninstall()
            NSApp.terminate(nil)
        } catch HelperInstaller.Failure.cancelled {
        } catch {
            Alerts.show(L10n.uninstallFailed, detail: "\(error)")
        }
    }
}
