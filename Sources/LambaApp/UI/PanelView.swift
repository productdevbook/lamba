import LambaCore
import SwiftUI

/// The popover shown from the menu bar item. Compact by design: one header line, then controls.
struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(model: model)
            LightPickerView(model: model)
            Divider().opacity(0.5)
            PomodoroView(model: model)
            Divider().opacity(0.5)
            FooterView(model: model)
        }
        .padding(14)
        .frame(width: 272)
    }
}

// MARK: - Header

/// App name with a small live LED, and the current mode on the right.
private struct HeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 10)
                .frame(width: 14, height: 14)
            Text(L10n.appName).font(.system(size: 13, weight: .semibold))
            Spacer()
            if !model.isSupported {
                Text(L10n.unsupportedShort)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(L10n.unsupportedBody)
            } else if model.error != nil {
                Button(action: model.reinstallHelper) {
                    Label(L10n.fixConnection, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(PressableStyle())
                .help(model.error ?? "")
            } else {
                Text(model.pomodoro == nil ? L10n.modeTitle(model.mode) : L10n.pomodoroSection)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
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

// MARK: - Light picker

private struct LightPickerView: View {
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
        picker
            .disabled(!model.isSupported)
            .opacity(model.isSupported ? 1 : 0.4)
    }

    private var picker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(options, id: \.1) { mode, title in
                    OptionButton(isSelected: isSelected(mode), action: { model.select(mode) }) {
                        VStack(spacing: 4) {
                            LEDView(appearance: LightAppearance(mode: mode), size: 12)
                            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(effects, id: \.1) { mode, title, symbol in
                    OptionButton(isSelected: isSelected(mode), action: { model.select(mode) }) {
                        HStack(spacing: 4) {
                            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func isSelected(_ mode: LightMode) -> Bool {
        model.pomodoro == nil && model.mode == mode
    }
}

// MARK: - Pomodoro

private struct PomodoroView: View {
    @ObservedObject var model: AppModel
    /// Shared with Settings › General, so the last choice becomes the default.
    @AppStorage(Preferences.Key.defaultPresetID) private var presetID = PomodoroPreset.default.id

    var body: some View {
        if let snapshot = model.pomodoro {
            running(snapshot)
        } else {
            idle
        }
    }

    /// Preset choice and a start button on one line.
    private var idle: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(PomodoroPreset.all) { preset in
                OptionButton(isSelected: presetID == preset.id, action: { presetID = preset.id }) {
                    Text(preset.title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .padding(.vertical, 5)
                }
            }
            IconButton(symbol: "play.fill", help: L10n.pomodoroStart, tint: Theme.orange, action: model.startPomodoro)
        }
    }

    private func running(_ snapshot: PomodoroSnapshot) -> some View {
        let color = Theme.color(for: snapshot.phase)
        let sessions = model.pomodoroSettings?.sessionsBeforeLongBreak ?? 4
        return HStack(spacing: 10) {
            ProgressRing(progress: model.pomodoroProgress, color: color, isPaused: snapshot.isPaused)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.formattedRemaining)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(snapshot.isPaused ? L10n.paused : L10n.phaseName(snapshot.phase))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                SessionDots(completed: snapshot.completedWorkSessions % sessions, total: sessions)
            }
            Spacer(minLength: 0)
            if snapshot.isPaused {
                IconButton(symbol: "play.fill", help: L10n.pomodoroResume, action: model.resumePomodoro)
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

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color.opacity(isPaused ? 0.45 : 1), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

private struct SessionDots: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Theme.orange : Color.primary.opacity(0.12))
                    .frame(width: 10, height: 3)
            }
        }
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

/// Equal-width selectable tile used for light modes and presets.
private struct OptionButton<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Theme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
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
