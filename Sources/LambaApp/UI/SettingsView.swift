import LambaCore
import ServiceManagement
import SwiftUI

/// Settings window: a sidebar of pages, like System Settings.
struct SettingsView: View {
    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case general, dock, contexts, integrations, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: return L10n.settingsGeneral
            case .dock: return L10n.dockTab
            case .contexts: return L10n.ctxTab
            case .integrations: return L10n.settingsIntegrations
            case .about: return L10n.settingsAbout
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .dock: return "dock.rectangle"
            case .contexts: return "square.stack.3d.up"
            case .integrations: return "sparkles"
            case .about: return "info.circle"
            }
        }

        var color: Color {
            switch self {
            case .general: return .gray
            case .dock: return .blue
            case .contexts: return .purple
            case .integrations: return .orange
            case .about: return .secondary
            }
        }
    }

    @ObservedObject var model: AppModel
    @ObservedObject var router: SettingsRouter

    init(model: AppModel, router: SettingsRouter) {
        self.model = model
        self.router = router
    }

    /// A fixed page, for snapshots.
    init(model: AppModel, tab: Tab) {
        let router = SettingsRouter()
        router.tab = tab
        self.init(model: model, router: router)
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: Binding(get: { router.tab }, set: { if let tab = $0 { router.tab = tab } })) { tab in
                SidebarRow(tab: tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            page.navigationTitle(router.tab.title)
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    private struct SidebarRow: View {
        let tab: Tab

        var body: some View {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab.color.gradient))
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch router.tab {
        case .general: GeneralSettings()
        case .dock: DockSettings(model: model)
        case .contexts: ContextSettingsView(contexts: model.contexts)
        case .integrations: IntegrationSettings(model: model)
        case .about: AboutSettings(model: model)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Preferences.Key.defaultPresetID) private var presetID = PomodoroPreset.default.id
    @AppStorage(Preferences.Key.longBreakMinutes) private var longBreak = 15.0
    @AppStorage(Preferences.Key.sessionsBeforeLongBreak) private var sessions = 4
    @AppStorage(Preferences.Key.playSounds) private var playSounds = true
    @AppStorage(Preferences.Key.flashOnPhaseChange) private var flash = true
    @AppStorage(Preferences.Key.haptics) private var haptics = true
    @AppStorage(Preferences.Key.keyboardFlash) private var keyboardFlash = true
    @AppStorage(Preferences.Key.capsLockFlash) private var capsLockFlash = true
    @AppStorage(Preferences.Key.keyboardMoods) private var keyboardMoods = true
    @AppStorage(Preferences.Key.keyboardOffAfter) private var keyboardOffAfter = true
    @AppStorage(Preferences.Key.keyboardNightDim) private var keyboardNightDim = true
    @AppStorage(Preferences.Key.keyboardNightStart) private var nightStart = 20
    @AppStorage(Preferences.Key.keyboardNightEnd) private var nightEnd = 8
    @AppStorage(Preferences.Key.keyboardBrightness) private var keyboardBrightness = 0.5
    @AppStorage(Preferences.Key.hapticWaveform) private var waveform = HapticStyle.default.waveform
    @AppStorage(Preferences.Key.hapticIntensity) private var intensity = HapticStyle.default.intensity
    @AppStorage(Preferences.Key.hapticPulses) private var pulses = HapticStyle.default.pulses

    private var nightHours: some View {
        HStack {
            Picker(L10n.keyboardNightStart, selection: $nightStart) { hourOptions }
            Picker(L10n.keyboardNightEnd, selection: $nightEnd) { hourOptions }
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
    }

    private var hapticStyle: HapticStyle { HapticStyle(waveform: waveform, intensity: intensity, pulses: pulses) }
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.current
    @State private var sleepDisabled = false
    @State private var sleepError: String?
    private let launchLanguage = AppLanguage.current

    var body: some View {
        Form {
            Section {
                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, perform: setLaunchAtLogin)
                Picker(L10n.language, selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: language) { $0.apply() }
                if language != launchLanguage {
                    HStack {
                        Text(L10n.languageRestartHint).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.languageRestart, action: AppRelauncher.relaunch)
                    }
                }
            }
            Section {
                Toggle(L10n.sleepDisabled, isOn: Binding(get: { sleepDisabled }, set: setSleep))
            } footer: {
                Text(sleepError ?? L10n.sleepFooter)
                    .font(.system(size: 11))
                    .foregroundStyle(sleepError == nil ? Color.secondary : Theme.orange)
            }
            Section(L10n.pomodoroSection) {
                Picker(L10n.defaultDuration, selection: $presetID) {
                    ForEach(PomodoroPreset.all) { Text(L10n.presetLabel($0)).tag($0.id) }
                }
                Picker(L10n.longBreak, selection: $longBreak) {
                    ForEach([10.0, 15, 20, 30], id: \.self) { Text(L10n.minutes(Int($0))).tag($0) }
                }
                Picker(L10n.sessionsBeforeLongBreak, selection: $sessions) {
                    ForEach(2...6, id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle(L10n.playSounds, isOn: $playSounds)
            }
            Section(L10n.lightsSection) {
                Toggle(L10n.flashOnPhaseChange, isOn: $flash)
                Toggle(L10n.keyboardFlash, isOn: $keyboardFlash)
                Toggle(L10n.keyboardOffAfter, isOn: $keyboardOffAfter)
                LabeledContent(L10n.keyboardBrightness) {
                    Slider(value: $keyboardBrightness, in: 0.05...1).frame(width: 160)
                }
                Toggle(L10n.keyboardNightDim, isOn: $keyboardNightDim)
                if keyboardNightDim { nightHours }
                Toggle(L10n.capsLockFlash, isOn: $capsLockFlash)
                Toggle(L10n.keyboardMoods, isOn: $keyboardMoods)
            }
            Section {
                Toggle(L10n.haptics, isOn: $haptics)
                Picker(L10n.hapticsWaveform, selection: $waveform) {
                    ForEach(HapticStyle.waveforms, id: \.self) { id in
                        Text(id == HapticStyle.default.waveform ? L10n.hapticsWaveformRecommended(id) : L10n.hapticsWaveformName(id)).tag(id)
                    }
                }
                LabeledContent(L10n.hapticsIntensity) {
                    HStack(spacing: 8) {
                        Slider(value: $intensity, in: HapticStyle.intensityRange, step: 0.25) { editing in
                            if !editing { preview() } // play once the knob is released
                        }
                        .frame(width: 160)
                        Text(intensity.formatted(.number.precision(.fractionLength(2)).locale(L10n.locale)))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Picker(L10n.hapticsPulses, selection: $pulses) {
                    ForEach(Array(HapticStyle.pulseRange), id: \.self) { Text("\($0)").tag($0) }
                }
                HStack {
                    Button(L10n.hapticsReset) {
                        Preferences.resetHapticStyle()
                        waveform = HapticStyle.default.waveform
                        intensity = HapticStyle.default.intensity
                        pulses = HapticStyle.default.pulses
                    }
                    .disabled(hapticStyle == .default)
                    Spacer()
                    Button(action: preview) {
                        Label(L10n.hapticsTest, systemImage: "waveform")
                    }
                }
            } header: {
                Text(L10n.hapticsSection)
            } footer: {
                Text(L10n.hapticsFooter).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { SystemSleep.read { sleepDisabled = $0 } }
        .onChange(of: waveform) { _ in preview() }
        .onChange(of: pulses) { _ in preview() }
    }

    /// Plays the style being edited, so changes can be felt right away.
    private func preview() {
        Haptics.shared.pulse(style: hapticStyle)
    }

    private func setSleep(_ disabled: Bool) {
        do {
            try SystemSleep.set(disabled: disabled)
            sleepError = nil
        } catch {
            sleepError = L10n.sleepFailed
        }
        SystemSleep.read { sleepDisabled = $0 }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            Alerts.show(L10n.launchAtLoginFailed, detail: error.localizedDescription)
        }
    }
}

// MARK: - Dock

private struct DockSettings: View {
    @ObservedObject var model: AppModel
    @AppStorage(Preferences.Key.dockEnabled) private var enabled = false
    @AppStorage(Preferences.Key.dockStyle) private var style = DockStyle.strip
    @AppStorage(Preferences.Key.hideAppleDock) private var hideAppleDock = true
    @AppStorage(Preferences.Key.dockIconSize) private var iconSize = 48.0
    @AppStorage(Preferences.Key.dockMagnification) private var magnification = 1.6
    @AppStorage(Preferences.Key.dockDownloads) private var showDownloads = true

    var body: some View {
        Form {
            Section {
                Toggle(L10n.dockEnabled, isOn: $enabled)
                Toggle(L10n.dockHideApple, isOn: $hideAppleDock).disabled(!enabled)
            } footer: {
                Text(L10n.dockHideAppleFooter).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                Picker(L10n.dockStyle, selection: $style) {
                    Text(L10n.dockStyleIslands).tag(DockStyle.islands)
                    Text(L10n.dockStyleStrip).tag(DockStyle.strip)
                    Text(L10n.dockStyleClassic).tag(DockStyle.classic)
                }
                .pickerStyle(.segmented)
                if style == .classic {
                    LabeledContent(L10n.dockSize) {
                        Slider(value: $iconSize, in: 32...80, step: 4)
                    }
                    LabeledContent(L10n.dockMagnification) {
                        Slider(value: $magnification, in: 1...2.2, step: 0.1)
                    }
                } else {
                    Toggle(L10n.dockShowDownloads, isOn: $showDownloads)
                    Text(L10n.dockStyleStripFooter).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.dockAppearance)
            }
            .disabled(!enabled)
            Section {
                Button(L10n.dockReimport, action: model.reimportDock)
            } header: {
                Text(L10n.dockApps)
            } footer: {
                Text(L10n.dockAppsFooter).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Integrations

private struct IntegrationSettings: View {
    @ObservedObject var model: AppModel
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section {
                ConnectionRow(
                    title: L10n.connHooksTitle, caption: L10n.connHooksCaption, symbol: "bell.badge",
                    isConnected: { ClaudeHooks.isInstalled },
                    connect: { done in done(Result { try ClaudeHooks.install() }) }
                )
                ConnectionRow(
                    title: L10n.connMCPTitle, caption: L10n.connMCPCaption, symbol: "terminal",
                    isConnected: { ClaudeConnections.isClaudeCodeConnected },
                    connect: ClaudeConnections.connectClaudeCode
                )
                if ClaudeConnections.isDesktopInstalled {
                    ConnectionRow(
                        title: L10n.connDesktopTitle, caption: L10n.connDesktopCaption, symbol: "macwindow",
                        isConnected: { ClaudeConnections.isDesktopConnected },
                        connect: { done in done(Result { try ClaudeConnections.connectDesktop() }) }
                    )
                }
            } header: {
                Text(L10n.connSection)
            }
            RemoteMachinesSection(model: model)
            Section {
                DisclosureGroup(L10n.connAdvanced, isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        CopyableSnippet(title: L10n.claudeCodeTitle, caption: L10n.claudeCodeCaption, text: Integrations.claudeCodeCommand)
                        CopyableSnippet(title: L10n.claudeDesktopTitle, caption: L10n.claudeDesktopCaption, text: Integrations.claudeDesktopConfig)
                        CopyableSnippet(title: L10n.hooksTitle, caption: L10n.hooksCaption, text: Integrations.claudeCodeHooks)
                        CopyableSnippet(title: L10n.cliTitle, caption: L10n.cliCaption, text: Integrations.cliExamples)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// "Claude Code notifications  ✓ Connected" or "[Connect]", with progress and errors.
private struct ConnectionRow: View {
    let title: String
    let caption: String
    let symbol: String
    let isConnected: () -> Bool
    let connect: (@escaping (Result<Void, Error>) -> Void) -> Void

    @State private var connected = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                if let error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Theme.orange).textSelection(.enabled)
                }
            }
            Spacer()
            if connected {
                Label(L10n.connConnected, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.green)
            } else if working {
                ProgressView().controlSize(.small)
            } else {
                Button(L10n.connConnect, action: run)
            }
        }
        .onAppear { connected = isConnected() }
    }

    private func run() {
        working = true
        error = nil
        connect { result in
            working = false
            switch result {
            case .success: connected = true
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }
}

/// A titled code block with a copy button that confirms briefly.
private struct CopyableSnippet: View {
    let title: String
    let caption: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: copy) {
                    Label(copied ? L10n.copied : L10n.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
        .padding(.vertical, 2)
    }

    private func copy() {
        Integrations.copy(text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.appName).font(.system(size: 15, weight: .semibold))
                        Text(L10n.version(LambaVersion.current)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if Updater.isConfigured {
                UpdatesSection()
            }
            Section(L10n.helperSection) {
                LabeledContent(L10n.helperStatus) {
                    HStack(spacing: 5) {
                        Circle().fill(model.error == nil ? Theme.green : .red).frame(width: 7, height: 7)
                        Text(model.error == nil ? L10n.helperRunning : L10n.helperNotRunning)
                    }
                }
                LabeledContent(L10n.cliLocation, value: Integrations.cliPath)
                HStack {
                    Button(L10n.reinstallHelper, action: model.reinstallHelper)
                    Spacer()
                    Button(L10n.uninstall, role: .destructive, action: model.uninstall)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings › About: automatic update checks and "Check for Updates…".
private struct UpdatesSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section(L10n.updatesSection) {
            Toggle(L10n.updatesAutomatic, isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
            HStack {
                Spacer()
                Button(L10n.checkForUpdates, action: updater.checkForUpdates).disabled(!updater.canCheck)
            }
        }
    }
}
