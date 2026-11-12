import LambaCore
import SwiftUI

/// The menu bar panel. For people who don't use the Lamba Dock it is the whole app: focus
/// (Pomodoro), Claude sessions and permission requests, the light, quick toggles and the context.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @StateObject private var toggles = QuickToggles()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(model: model, contexts: model.contexts)
            FocusCard(model: model)
            if showsClaude { ClaudeCard(model: model) }
            LightRow(model: model)
            TogglesRow(toggles: toggles)
            FooterView(model: model)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { toggles.refresh() }
    }

    private var showsClaude: Bool {
        model.permission != nil || !model.agentSessions.isEmpty || ClaudeHooks.isInstalled
    }
}

// MARK: - Header

/// App name and live LED; the current context on the right (click to switch).
private struct HeaderView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var contexts: ContextEngine

    var body: some View {
        HStack(spacing: 8) {
            LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 10)
                .frame(width: 14, height: 14)
            Text(L10n.appName).font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.isSupported, model.error != nil {
                Button(action: model.reinstallHelper) {
                    Label(L10n.fixConnection, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(PressableStyle())
                .help(model.error ?? "")
            } else if let current = contexts.current, contexts.contexts.count > 1 {
                Menu {
                    ForEach(contexts.contexts) { context in
                        Button {
                            contexts.select(context.id)
                        } label: {
                            if context.id == current.id {
                                Label(context.name, systemImage: "checkmark")
                            } else {
                                Text(context.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Color(nsColor: current.color.color)).frame(width: 7, height: 7)
                        Text(current.name).font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.cardBackground))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

// MARK: - Focus

/// The hero card: a big ring with the clock (idle) or the time left (running).
private struct FocusCard: View {
    @ObservedObject var model: AppModel
    /// Shared with Settings › General, so the last choice becomes the default.
    @AppStorage(Preferences.Key.defaultPresetID) private var presetID = PomodoroPreset.default.id

    var body: some View {
        HStack(spacing: 14) {
            dial
            VStack(alignment: .leading, spacing: 8) {
                if let snapshot = model.pomodoro { running(snapshot) } else { idle }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Card(tint: model.pomodoro.map { Theme.color(for: $0.phase) }))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.pomodoro == nil)
    }

    private var dial: some View {
        ZStack {
            if let snapshot = model.pomodoro {
                ProgressRing(progress: model.pomodoroProgress, color: Theme.color(for: snapshot.phase), isPaused: snapshot.isPaused, lineWidth: 5)
                Text(snapshot.formattedRemaining)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            } else {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
        }
        .frame(width: 72, height: 72)
    }

    private var idle: some View {
        Group {
            Text(L10n.pomodoroSection).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 4) {
                ForEach(PomodoroPreset.all) { preset in
                    Chip(title: preset.title, isSelected: presetID == preset.id) { presetID = preset.id }
                }
            }
            Button(action: model.startPomodoro) {
                Label(L10n.pomodoroStart, systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.orange))
            }
            .buttonStyle(PressableStyle())
        }
    }

    @ViewBuilder
    private func running(_ snapshot: PomodoroSnapshot) -> some View {
        let sessions = model.pomodoroSettings?.sessionsBeforeLongBreak ?? 4
        Text(snapshot.isPaused ? L10n.paused : L10n.phaseName(snapshot.phase))
            .font(.system(size: 13, weight: .semibold))
        SessionDots(completed: snapshot.completedWorkSessions % sessions, total: sessions, color: Theme.color(for: snapshot.phase))
        HStack(spacing: 6) {
            if snapshot.isPaused {
                IconButton(symbol: "play.fill", help: L10n.pomodoroResume, tint: Theme.color(for: snapshot.phase), action: model.resumePomodoro)
            } else {
                IconButton(symbol: "pause.fill", help: L10n.pomodoroPause, action: model.pausePomodoro)
            }
            IconButton(symbol: "forward.end.fill", help: L10n.pomodoroSkip, action: model.skipPomodoro)
            IconButton(symbol: "stop.fill", help: L10n.pomodoroStop, action: model.stopPomodoro)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color
    let isPaused: Bool
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color.opacity(isPaused ? 0.45 : 1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

private struct SessionDots: View {
    let completed: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? color : Color.primary.opacity(0.12))
                    .frame(width: 12, height: 3)
            }
        }
    }
}

// MARK: - Claude

/// A waiting permission (Allow / Deny), then the latest sessions; click one to open its terminal.
private struct ClaudeCard: View {
    @ObservedObject var model: AppModel

    private var sessions: [AgentSessionInfo] {
        let all = model.agentSessions
        return Array((all.filter { $0.state.event != .done } + all.filter { $0.state.event == .done }).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundStyle(AgentIcon.claude)
                Text("Claude").font(.system(size: 11, weight: .semibold))
                Spacer()
                if !model.remoteMachines.isEmpty {
                    Text(machinesLine).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            if let prompt = model.permission {
                PermissionRow(prompt: prompt, answer: model.answerPermission) { model.showAgent() }
            }
            if sessions.isEmpty && model.permission == nil {
                Text(L10n.agentNoSessions)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(sessions) { session in
                AgentSessionRow(session: session).onTapGesture { model.showAgent(session) }
            }
        }
        .padding(4)
        .background(Card(tint: nil))
    }

    private var machinesLine: String {
        let connected = model.remoteMachines.filter(\.isConnected).count
        return "\(L10n.agentThisMac) + \(connected)/\(model.remoteMachines.count) SSH"
    }
}

private struct PermissionRow: View {
    let prompt: PermissionPrompt
    let answer: (PermissionDecision) -> Void
    let show: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.permissionTitle(L10n.agentActivity(prompt.detail.tool)))
                    .font(.system(size: 12.5, weight: .semibold))
                if let target = prompt.detail.target {
                    Text(target).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .onTapGesture(perform: show)
            Spacer(minLength: 4)
            IconButton(symbol: "xmark", help: L10n.permissionDeny) { answer(.deny) }
            IconButton(symbol: "checkmark", help: L10n.permissionAllow, tint: Theme.green) { answer(.allow) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.orange.opacity(0.14)))
    }
}

// MARK: - Light

/// The MagSafe light: four swatches and the blinking effects in a menu.
private struct LightRow: View {
    @ObservedObject var model: AppModel

    private let options: [(LightMode, String)] = [
        (.solid(.green), L10n.green),
        (.solid(.orange), L10n.orange),
        (.solid(.off), L10n.off),
        (.solid(.system), L10n.automatic),
    ]

    private let effects: [(LightMode, String, String)] = [
        (.solid(.orangeBlinkSlow), L10n.blinkSlow, "tortoise.fill"),
        (.solid(.orangeBlinkFast), L10n.blinkFast, "hare.fill"),
        (.pattern(.alternate), L10n.alternate, "arrow.left.arrow.right"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.lightsSection)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            ForEach(options, id: \.1) { mode, title in
                Button { model.select(mode) } label: {
                    LEDView(appearance: LightAppearance(mode: mode), size: 13)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(model.mode == mode ? Color.accentColor.opacity(0.18) : Theme.cardBackground))
                        .overlay(Circle().stroke(model.mode == mode ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .help(title)
            }
            Menu {
                ForEach(effects, id: \.1) { mode, title, symbol in
                    Button { model.select(mode) } label: { Label(title, systemImage: symbol) }
                }
            } label: {
                Image(systemName: isEffect ? "sparkles" : "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isEffect ? Color.accentColor.opacity(0.18) : Theme.cardBackground))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .disabled(!model.isSupported)
        .opacity(model.isSupported ? 1 : 0.4)
        .help(model.isSupported ? "" : L10n.unsupportedBody)
    }

    private var isEffect: Bool { effects.contains { $0.0 == model.mode } }
}

// MARK: - Quick toggles

private struct TogglesRow: View {
    @ObservedObject var toggles: QuickToggles

    var body: some View {
        HStack(spacing: 6) {
            tile("cup.and.saucer.fill", L10n.togglesKeepAwake, on: toggles.keepAwake, tint: Theme.orange, action: toggles.toggleKeepAwake)
            tile("moon.zzz.fill", L10n.togglesNoSleep, on: toggles.sleepDisabled, tint: .blue, action: toggles.toggleSleepDisabled)
            tile("circle.lefthalf.filled", L10n.togglesDarkMode, on: toggles.darkMode, tint: .purple, action: toggles.toggleDarkMode)
            tile(toggles.micMuted ? "mic.slash.fill" : "mic.fill", L10n.togglesMic, on: toggles.micMuted, tint: .red, action: toggles.toggleMic)
        }
    }

    private func tile(_ symbol: String, _ title: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? tint : .secondary)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? tint.opacity(0.18) : Theme.cardBackground))
        }
        .buttonStyle(PressableStyle())
        .help(title)
    }
}

/// A small LED dot that animates blinking modes.
struct LEDView: View {
    let appearance: LightAppearance
    let size: CGFloat

    var body: some View {
        if appearance.isAnimated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                led(appearance.color(at: context.date))
            }
        } else {
            led(appearance.color(at: Date()))
        }
    }

    @ViewBuilder
    private func led(_ color: Color?) -> some View {
        ZStack {
            if appearance.isAutomatic {
                Circle()
                    .fill(AngularGradient(colors: [Theme.green, Theme.orange, Theme.green], center: .center))
            } else if let color {
                Circle().fill(color).blur(radius: size * 0.3).opacity(0.5).scaleEffect(1.3)
                Circle().fill(color)
            } else {
                Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.12), value: color == nil)
    }
}

// MARK: - Footer

private struct FooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            Button(action: model.openSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text(L10n.settings)
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(",")
            Spacer()
            Button(action: model.openStatistics) {
                Image(systemName: "chart.bar.fill").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PressableStyle())
            .help(L10n.statistics)
            Button(action: model.quit) {
                Image(systemName: "power").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(PressableStyle())
            .help(L10n.quit)
            .keyboardShortcut("q")
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Shared controls

/// A small selectable pill (Pomodoro presets).
private struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Theme.cardBackground))
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// The panel's card surface, lightly tinted by the Pomodoro phase.
private struct Card: View {
    let tint: Color?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.cardBackground)
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08))
                }
            }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint == nil ? Color.primary : Color.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint ?? Color.primary.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
