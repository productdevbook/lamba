import Foundation
import LambaCore

/// All user-facing UI text. Translations live in `scripts/strings.py`, which generates
/// `Support/Localization/<lang>.lproj/Localizable.strings` (English, Turkish, German).
enum L10n {
    static let appName = "Lamba"

    static let fixConnection = tr("fixConnection")

    // Light
    static let green = tr("light.green")
    static let orange = tr("light.orange")
    static let off = tr("light.off")
    static let automatic = tr("light.automatic")
    static let blinkSlow = tr("light.slow")
    static let blinkFast = tr("light.fast")
    static let alternate = tr("light.alternate")
    static let resetLight = tr("resetLight")

    static func modeTitle(_ mode: LightMode) -> String {
        switch mode {
        case .solid(.green): return green
        case .solid(.orange): return orange
        case .solid(.off): return off
        case .solid(.system): return automatic
        case .solid(.orangeBlinkSlow): return tr("mode.blinkSlow")
        case .solid(.orangeBlinkFast): return tr("mode.blinkFast")
        case .pattern: return tr("mode.alternate")
        }
    }

    // Pomodoro
    static let pomodoroSection = "Pomodoro"
    static let pomodoroStart = tr("pomodoro.start")
    static let pomodoroStartMenu = tr("pomodoro.startMenu")
    static let pomodoroPause = tr("pomodoro.pause")
    static let pomodoroResume = tr("pomodoro.resume")
    static let pomodoroSkip = tr("pomodoro.skip")
    static let pomodoroStop = tr("pomodoro.stop")
    static let paused = tr("pomodoro.paused")

    static func phaseName(_ phase: PomodoroPhase) -> String {
        switch phase {
        case .work: return tr("phase.work")
        case .shortBreak: return tr("phase.shortBreak")
        case .longBreak: return tr("phase.longBreak")
        }
    }

    static func sessionCount(_ count: Int) -> String {
        count == 0 ? tr("sessions.first") : format("sessions.completed", count)
    }

    // Settings
    static let settings = tr("settings")
    static let settingsTitle = tr("settings.title")
    static let settingsGeneral = tr("settings.general")
    static let settingsIntegrations = tr("settings.integrations")
    static let settingsAbout = tr("settings.about")
    static let launchAtLogin = tr("launchAtLogin")
    static let launchAtLoginFailed = tr("launchAtLoginFailed")
    static let language = tr("language")
    static let languageSystem = tr("language.system")
    static let languageRestartHint = tr("language.restartHint")
    static let languageRestart = tr("language.restart")
    static let defaultDuration = tr("defaultDuration")
    static let longBreak = tr("longBreak")
    static let sessionsBeforeLongBreak = tr("sessionsBeforeLongBreak")
    static let playSounds = tr("playSounds")
    static let flashOnPhaseChange = tr("flashOnPhaseChange")
    static let haptics = tr("haptics")
    static let hapticsTest = tr("haptics.test")
    static let hapticsSection = tr("haptics.section")
    static let hapticsWaveform = tr("haptics.waveform")
    static let hapticsIntensity = tr("haptics.intensity")
    static let hapticsPulses = tr("haptics.pulses")
    static let hapticsReset = tr("haptics.reset")
    static func hapticsWaveformName(_ id: Int) -> String { format("haptics.waveform.name", id) }
    static func hapticsWaveformRecommended(_ id: Int) -> String { format("haptics.waveform.recommended", id) }
    static let hapticsFooter = tr("haptics.footer")

    static let dockTab = tr("dock.tab")
    static let dockEnabled = tr("dock.enabled")
    static let dockHideApple = tr("dock.hideApple")
    static let dockHideAppleFooter = tr("dock.hideAppleFooter")
    static let dockSize = tr("dock.size")
    static let dockStyle = tr("dock.style")

    static let hooksInstall = tr("hooks.install")
    static let hooksInstalled = tr("hooks.installed")
    static let hooksInstallFailed = tr("hooks.installFailed")

    static let agentWorking = tr("agent.working")
    static func agentWorkingMany(_ count: Int) -> String { format("agent.workingMany", count) }
    static let agentWaiting = tr("agent.waiting")
    static let agentDone = tr("agent.done")
    static let agentSession = tr("agent.session")
    static let agentThisMac = tr("agent.thisMac")
    static func agentFinished(_ name: String) -> String { format("agent.finished", name) }
    static let agentConnected = tr("agent.connected")
    static let agentOffline = tr("agent.offline")
    static let agentNoSessions = tr("agent.noSessions")
    static func agentAgo(_ time: String) -> String { format("agent.ago", time) }

    /// "Editing", "Running a command", … for a Claude Code tool name.
    static func agentActivity(_ tool: String) -> String {
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return tr("agent.tool.edit")
        case "Read": return tr("agent.tool.read")
        case "Bash", "BashOutput", "KillShell": return tr("agent.tool.bash")
        case "Grep", "Glob", "LS": return tr("agent.tool.search")
        case "WebFetch", "WebSearch": return tr("agent.tool.web")
        case "Task", "Agent": return tr("agent.tool.agent")
        case "TodoWrite", "ExitPlanMode": return tr("agent.tool.plan")
        default:
            // MCP tools (`mcp__chrome-devtools__take_snapshot`) show their server, which stays the
            // same from call to call, instead of each call's verb.
            let parts = tool.components(separatedBy: "__")
            let name = tool.hasPrefix("mcp__") && parts.count >= 2 ? parts[1] : tool
            return format("agent.tool.other", name)
        }
    }

    static func permissionTitle(_ activity: String) -> String { format("permission.title", activity) }
    static let permissionAllow = tr("permission.allow")
    static let permissionDeny = tr("permission.deny")
    static let permissionAsk = tr("permission.ask")

    static let musicNext = tr("music.next")
    static let musicPrevious = tr("music.previous")
    static func musicOpen(_ app: String) -> String { format("music.open", app) }

    static let meetingNow = tr("meeting.now")
    static func meetingIn(_ minutes: Int) -> String { format("meeting.in", minutes) }
    static let meetingJoin = tr("meeting.join")
    static let meetingOpenCalendar = tr("meeting.openCalendar")

    /// Short charger state for the Dock.
    static func dockCharge(_ state: ChargeState) -> String {
        switch state {
        case .charging: return tr("dock.charge.charging")
        case .notCharging: return tr("dock.charge.plugged")
        case .onBattery: return tr("dock.charge.battery")
        }
    }
    static let dockStyleStrip = tr("dock.style.strip")
    static let dockStyleClassic = tr("dock.style.classic")
    static let dockStyleIslands = tr("dock.style.islands")
    static let keyboardFlash = tr("settings.keyboardFlash")
    static let capsLockFlash = tr("settings.capsLockFlash")
    static let keyboardMoods = tr("settings.keyboardMoods")
    static let keyboardOffAfter = tr("keyboard.offAfter")
    static let keyboardNightDim = tr("keyboard.nightDim")
    static let dockStyleStripFooter = tr("dock.style.stripFooter")
    static let dockMagnification = tr("dock.magnification")
    static let dockAppearance = tr("dock.appearance")
    static let dockApps = tr("dock.apps")
    static let dockReimport = tr("dock.reimport")
    static let dockAppsFooter = tr("dock.appsFooter")
    static let dockOpen = tr("dock.open")
    static let dockShow = tr("dock.show")
    static let dockShowInFinder = tr("dock.showInFinder")
    static let dockKeep = tr("dock.keep")
    static let dockRemove = tr("dock.remove")
    static let dockMoveLeft = tr("dock.moveLeft")
    static let dockMoveRight = tr("dock.moveRight")
    static let dockHide = tr("dock.hide")
    static let dockQuit = tr("dock.quit")
    static let dockTrash = tr("dock.trash")
    static let dockLambaHelp = tr("dock.lambaHelp")

    static func minutes(_ value: Int) -> String { format("minutes", value) }

    static func presetLabel(_ preset: PomodoroPreset) -> String {
        format("preset", Int(preset.settings.workMinutes), Int(preset.settings.shortBreakMinutes))
    }

    // Integrations
    static let copy = tr("copy")
    static let copied = tr("copied")
    static let claudeCodeTitle = "Claude Code"
    static let claudeCodeCaption = tr("claudeCode.caption")
    static let claudeDesktopTitle = "Claude Desktop"
    static let claudeDesktopCaption = tr("claudeDesktop.caption")
    static let hooksTitle = tr("hooks.title")
    static let hooksCaption = tr("hooks.caption")
    static let cliTitle = tr("cli.title")
    static let cliCaption = tr("cli.caption")

    // About
    static func version(_ value: String) -> String { format("version", value) }
    static let helperSection = tr("helper.section")
    static let helperStatus = tr("helper.status")
    static let helperRunning = tr("helper.running")
    static let helperNotRunning = tr("helper.notRunning")
    static let cliLocation = tr("cli.location")
    static let reinstallHelper = tr("reinstall")
    static let uninstall = tr("uninstall")
    static let uninstallConfirm = tr("uninstall.confirm")
    static let uninstallDetail = tr("uninstall.detail")
    static let uninstallPrompt = tr("uninstall.prompt")
    static let uninstallFailed = tr("uninstall.failed")
    static let cancel = tr("cancel")

    // System
    static let quit = tr("quit")
    static let installPrompt = tr("install.prompt")
    static let installFailed = tr("install.failed")
    static let serverFailed = tr("server.failed")

    // Statistics
    static let statistics = tr("settings.statistics")
    static let export = tr("export")
    static let exportCSV = tr("export.csv")
    static let exportCopy = tr("export.copy")
    static let kpiFocus = tr("kpi.focus")
    static let kpiSessions = tr("kpi.sessions")
    static let kpiStreak = tr("kpi.streak")
    static let kpiFlashes = tr("kpi.flashes")
    static let dailyFocus = tr("chart.dailyFocus")
    static let chartMinutes = tr("chart.minutes")
    static let lightUsage = tr("usage.light")
    static let chargerUsage = tr("usage.charger")
    static let statsEmpty = tr("stats.empty")
    static let statsPrivacy = tr("stats.privacy")
    static let statsClear = tr("stats.clear")
    static let statsClearConfirm = tr("stats.clear.confirm")
    static let statsClearDetail = tr("stats.clear.detail")
    static let statsClearAction = tr("stats.clear.action")

    static func days(_ count: Int) -> String { format("range.days", count) }
    static func streakDays(_ count: Int) -> String { format("streak.days", count) }
    static func average(_ duration: String) -> String { format("chart.average", duration) }
    static func vsPrevious(_ delta: String) -> String { format("delta.vsPrevious", delta) }

    /// "2 h 5 min" style, in the app's language.
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(0, seconds.rounded())) ?? "0"
    }

    /// Name of a recorded light mode (`LightMode.name`).
    static func lightName(_ name: String) -> String {
        if name == LightPattern.alternate.name { return modeTitle(.pattern(.alternate)) }
        return LightState(rawValue: name).map { modeTitle(.solid($0)) } ?? name
    }

    /// Name of a recorded charger state (`ChargeState.name`).
    static func chargeName(_ name: String) -> String {
        switch name {
        case ChargeState.charging.name: return tr("charge.charging")
        case ChargeState.notCharging.name: return tr("charge.plugged")
        case ChargeState.onBattery.name: return tr("charge.battery")
        default: return name
        }
    }

    /// Locale matching the UI language, for dates, durations and numbers.
    static let locale = Locale(identifier: resolved.language)

    // Onboarding
    static let onboardingTitle = tr("onboarding.title")
    static let onboardingSubtitle = tr("onboarding.subtitle")
    static let onboardingLightTitle = tr("onboarding.light.title")
    static let onboardingLightBody = tr("onboarding.light.body")
    static let onboardingPomodoroTitle = tr("onboarding.pomodoro.title")
    static let onboardingPomodoroBody = tr("onboarding.pomodoro.body")
    static let onboardingClaudeTitle = tr("onboarding.claude.title")
    static let onboardingClaudeBody = tr("onboarding.claude.body")
    static let onboardingPassword = tr("onboarding.password")
    static let onboardingInstall = tr("onboarding.install")
    static let onboardingLater = tr("onboarding.later")
    static let onboardingDoneTitle = tr("onboarding.done.title")
    static let onboardingDoneBody = tr("onboarding.done.body")
    static let onboardingDone = tr("onboarding.done")
    static let unsupportedTitle = tr("unsupported.title")
    static let unsupportedBody = tr("unsupported.body")
    static let unsupportedShort = tr("unsupported.short")
    static let continueLabel = tr("continue")

    // MARK: - Lookup

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }

    private static var bundle: Bundle { resolved.bundle }

    /// The app bundle in release builds. Unbundled debug runs (`swift run`, snapshots) read the
    /// generated files from the source tree instead.
    private static let resolved: (bundle: Bundle, language: String) = {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return (Bundle.main, Bundle.main.preferredLocalizations.first ?? "en")
        }
        #if DEBUG
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Support/Localization").standardized
        if let root = Bundle(url: sourceRoot),
           let language = Bundle.preferredLocalizations(from: root.localizations, forPreferences: Locale.preferredLanguages).first,
           let bundle = Bundle(url: sourceRoot.appendingPathComponent("\(language).lproj")) {
            return (bundle, language)
        }
        #endif
        return (Bundle.main, "en")
    }()
}

/// Per-app language override (stored in the app's own `AppleLanguages` default, applied at launch).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, tr, de

    var id: String { rawValue }

    /// Language names are shown in their own language, as macOS does.
    var displayName: String {
        switch self {
        case .system: return L10n.languageSystem
        case .en: return "English"
        case .tr: return "Türkçe"
        case .de: return "Deutsch"
        }
    }

    static var current: AppLanguage {
        let override = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String]
        return override?.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
