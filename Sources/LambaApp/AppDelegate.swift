import AppKit
import LambaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let installer = HelperInstaller()
    private let power = PowerMonitor()
    private let activity = ActivityTracker()
    private let light = LightController(writer: HelperLightWriter())
    private lazy var pomodoro = PomodoroController(light: light)
    private let agents = AgentMonitor()
    private let tunnels = SSHTunnels()
    private var statisticsWindow: StatisticsWindowController?
    private lazy var router = RequestRouter(light: light, pomodoro: pomodoro, activity: activity, agents: agents)
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var dock: DockWindowController?
    private var model: AppModel?
    private var server: UnixSocketServer?
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        Preferences.registerDefaults()
        _ = Updater.shared // starts Sparkle's scheduled checks (release builds only)

        if (try? AppClient().send(.status)) != nil {
            // Another Lamba instance already owns the socket.
            NSApp.terminate(nil)
            return
        }

        let model = AppModel(light: light, pomodoro: pomodoro, router: router, installer: installer, power: power, activity: activity, agents: agents)
        let statusItem = StatusItemController(model: model)
        let settingsWindow = SettingsWindowController(model: model)
        model.openSettings = { [weak statusItem, weak settingsWindow] in
            statusItem?.closePopover()
            settingsWindow?.show()
        }
        let statisticsWindow = StatisticsWindowController(model: model)
        model.openStatistics = { [weak statusItem, weak statisticsWindow] in
            statusItem?.closePopover()
            statisticsWindow?.show()
        }
        self.statisticsWindow = statisticsWindow
        self.statusItem = statusItem
        let dock = DockWindowController(model: model)
        model.reimportDock = { [weak dock] in dock?.reimportApps() }
        self.dock = dock
        self.settingsWindow = settingsWindow
        light.onChange = { [weak statusItem, light, activity] in
            activity.lightModeChanged(light.mode)
            statusItem?.refresh()
        }
        pomodoro.onChange = { [weak statusItem] in statusItem?.refresh() }
        agents.onChange = { [weak model] in model?.refresh() }
        agents.onFinish = { [weak model] in model?.announce($0) }
        pomodoro.onFocusEnded = { [activity] in activity.focusEnded(start: $0, end: $1, completed: $2) }
        power.onChange = { [weak statusItem, power, activity] in
            activity.chargeStateChanged(power.state)
            statusItem?.refresh()
        }
        activity.lightModeChanged(light.mode)
        activity.chargeStateChanged(power.state)

        ensureHelper()
        startServer()
        router.tunnels = tunnels
        model.tunnels = tunnels
        tunnels.onChange = { [weak model] in model?.refresh() }
        tunnels.start()
        self.model = model
        model.contexts.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pomodoro.stop(restoreLight: false) // records an unfinished focus phase
        light.restoreSystemControl()
        activity.flush()
        dock?.tearDown()
        tunnels.stop()
        model?.contexts.stop()
        KeyboardLight.shared.mood = .normal // gives the keyboard light back to the user
        Thermals.shared.releaseFans()
    }

    /// First run explains the password prompt before it appears; later runs (e.g. after an update
    /// or moving the app) reinstall directly. Macs without a MagSafe LED never install the helper.
    private func ensureHelper() {
        guard HardwareSupport.hasMagSafeLED else {
            if !Preferences.onboardingCompleted {
                onboarding.show(step: .unsupported, install: { false }, finish: { Preferences.onboardingCompleted = true })
            }
            return
        }
        guard installer.needsInstall else {
            Preferences.onboardingCompleted = true
            return
        }
        if Preferences.onboardingCompleted {
            _ = installHelper()
        } else {
            onboarding.show(step: .welcome, install: installHelper, finish: { Preferences.onboardingCompleted = true })
        }
    }

    private func installHelper() -> Bool {
        do {
            try installer.install()
            light.set(light.mode) // apply the current mode now that the helper runs
            return true
        } catch HelperInstaller.Failure.cancelled {
            return false // the panel offers to install again
        } catch {
            Alerts.show(L10n.installFailed, detail: "\(error)")
            return false
        }
    }

    private func startServer() {
        do {
            try FileManager.default.createDirectory(at: LambaPaths.appSupportDirectory, withIntermediateDirectories: true)
            server = try UnixSocketServer(
                path: LambaPaths.appSocket,
                permissions: 0o600,
                queue: DispatchQueue(label: "dev.hamur.lamba.ipc"),
                authorize: { $0 == getuid() },
                asyncHandler: { [router] data, peer, reply in
                    DispatchQueue.main.async { router.handle(data, peer: peer, reply: reply) }
                }
            )
        } catch {
            Alerts.show(L10n.serverFailed, detail: "\(error)")
        }
    }
}
