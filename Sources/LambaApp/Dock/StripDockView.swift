import AppKit
import LambaCore
import SwiftUI

enum StripMetrics {
    static let height: CGFloat = 56
    static let bottomMargin: CGFloat = 10
    static let icon: CGFloat = 34
    static let inset: CGFloat = 8
}

/// The "strip" Dock: one long floating bar made of modules instead of a row of equal icons.
///
/// `[ Lamba status ] | app chips… | other apps… | [ clock · battery ] trash`
struct StripDockView: View {
    @ObservedObject var dock: DockModel
    @ObservedObject var model: AppModel
    @ObservedObject var layout: DockLayout
    let meetings: MeetingMonitor
    let nowPlaying: NowPlayingMonitor

    @State private var launching: Set<String> = []
    @AppStorage(Preferences.Key.dockDownloads) private var showDownloads = true
    @AppStorage(Preferences.Key.dockClipboard) private var showClipboard = true
    @AppStorage(Preferences.Key.dockConvert) private var showConvert = true
    @AppStorage(Preferences.Key.dockSystemStatus) private var showSystem = true
    /// Chip frames in window coordinates, to find the chip under the pointer. The Dock's own
    /// pointer tracking is used because SwiftUI hover doesn't fire while Lamba isn't active.
    @State private var chipFrames: [String: CGRect] = [:]

    private var hovered: String? {
        guard let x = layout.pointerX else { return nil }
        return chipFrames.first { $0.value.minX <= x && x <= $0.value.maxX }?.key
    }

    var body: some View {
        HStack(spacing: 6) {
            LambaModule(model: model)
            LiveCapsules(model: model, meetings: meetings, nowPlaying: nowPlaying)
            ModuleDivider()
            apps
            ModuleDivider()
            if showSystem { SystemStatusTile(onDark: true) }
            StatusModule(chargeState: model.chargeState)
            if showClipboard { ClipboardTile(onDark: true) }
            if showConvert { ConvertTile(onDark: true) }
                if showDownloads { DownloadsTile(onDark: true) }
            TrashChip()
        }
        .padding(StripMetrics.inset)
        .frame(height: StripMetrics.height)
        .background(background)
        .reportFrame(to: layout)
        .environment(\.colorScheme, .dark)
        .padding(.bottom, StripMetrics.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeStates)
        .animation(.easeOut(duration: 0.2), value: slotIDs)
        .onPreferenceChange(ChipFrames.self) { chipFrames = $0 }
        .onChange(of: runningPaths) { running in
            launching.subtract(running)
        }
    }

    private var allItems: [DockItem] { dock.pinned + dock.others }
    private var activeStates: [Bool] { allItems.map(\.isActive) }
    private var slotIDs: [String] { dock.slots.map(\.id) }
    private var runningPaths: [String] { allItems.filter(\.isRunning).map(\.path) }

    /// While a session's finish is announced, the apps step aside and their space becomes the
    /// notification; the Lamba module, capsules and status stay. Same size, no jump.
    private var apps: some View {
        let isAnnouncing = model.announcement != nil
        return HStack(spacing: 6) {
            ForEach(dock.pinned) { chip(for: $0) }
            if !dock.others.isEmpty {
                ModuleDivider()
                ForEach(dock.others) { chip(for: $0) }
            }
        }
        .opacity(isAnnouncing ? 0 : 1)
        .scaleEffect(isAnnouncing ? 0.96 : 1)
        .allowsHitTesting(!isAnnouncing)
        .overlay { banner }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.announcement?.id)
    }

    @ViewBuilder
    private var banner: some View {
        if let session = model.announcement {
            FinishedBanner(session: session) {
                model.dismissAnnouncement()
                model.showAgent(session)
            }
            .transition(.opacity.combined(with: .scale(scale: 1.04)))
        }
    }

    private func chip(for item: DockItem) -> some View {
        AppChip(
            item: item,
            isLaunching: launching.contains(item.path),
            dock: dock,
            open: {
                if !item.isRunning {
                    // Some apps (Apps, Launchpad) never show up as running; stop pulsing after a while.
                    let path = item.path
                    launching.insert(path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { launching.remove(path) }
                }
                dock.open(item)
            }
        )
        .overlay(alignment: .top) {
            if hovered == item.id {
                NameLabel(text: item.name)
                    .offset(y: -(StripMetrics.inset + 30))
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .allowsHitTesting(false)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ChipFrames.self, value: [item.id: proxy.frame(in: .global)])
        })
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private var background: some View {
        let shape = Capsule(style: .continuous)
        return ZStack {
            VisualEffect().clipShape(shape)
            shape.fill(Color.black.opacity(0.25))
            // A soft wash of the LED color from the left, where the Lamba module sits.
            shape.fill(LinearGradient(colors: [ledColor.opacity(0.22), .clear], startPoint: .leading, endPoint: .init(x: 0.45, y: 0.5)))
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var ledColor: Color { LambaModule.color(for: model.visibleLight) ?? .clear }
}

// MARK: - Lamba module

/// LED, current light or Pomodoro phase, and a long progress fill for the running session.
struct LambaModule: View {
    @ObservedObject var model: AppModel
    @State private var isHovered = false

    var body: some View {
        Group {
            if model.pomodoro != nil { expanded } else { compact }
        }
        .frame(maxHeight: .infinity)
        .background(progressFill)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(isHovered ? 0.12 : 0.07)))
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: model.togglePomodoro)
        .contextMenu { LambaMenu(model: model) }
        .help(L10n.dockLambaHelp)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.pomodoro == nil)
    }

    /// Idle: just the LED, as a round button.
    private var compact: some View {
        LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 12)
            .frame(width: StripMetrics.height - StripMetrics.inset * 2)
            .transition(.opacity)
    }

    /// While a Pomodoro runs: phase, time left and a progress fill across the whole module.
    private var expanded: some View {
        HStack(spacing: 10) {
            LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 12)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(width: 170)
        .transition(.opacity)
    }

    private var title: String {
        if let pomodoro = model.pomodoro { return L10n.phaseName(pomodoro.phase) }
        return L10n.appName + " · " + L10n.modeTitle(model.mode)
    }

    private var subtitle: String {
        if let pomodoro = model.pomodoro {
            return pomodoro.isPaused ? "\(pomodoro.formattedRemaining) · \(L10n.paused)" : pomodoro.formattedRemaining
        }
        return isHovered ? L10n.pomodoroStartMenu : L10n.dockCharge(model.chargeState)
    }

    private var symbol: String {
        guard let pomodoro = model.pomodoro else { return "play.fill" }
        return pomodoro.isPaused ? "play.fill" : "pause.fill"
    }

    @ViewBuilder
    private var progressFill: some View {
        if let pomodoro = model.pomodoro {
            GeometryReader { proxy in
                let color = Theme.color(for: pomodoro.phase)
                LinearGradient(colors: [color.opacity(0.15), color.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * model.pomodoroProgress)
                    .animation(.linear(duration: 1), value: model.pomodoroProgress)
            }
            .opacity(pomodoro.isPaused ? 0.5 : 1)
        }
    }

    static func color(for light: LightState) -> Color? {
        switch light {
        case .green: return Theme.green
        case .orange, .orangeBlinkSlow, .orangeBlinkFast: return Theme.orange
        case .off, .system: return nil
        }
    }
}

// MARK: - App chips

/// An app icon; the active app sits on a soft pill.
struct AppChip: View {
    let item: DockItem
    let isLaunching: Bool
    @ObservedObject var dock: DockModel
    let open: () -> Void

    @State private var isTargeted = false
    @State private var pulse = false

    var body: some View {
        Image(nsImage: item.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: StripMetrics.icon, height: StripMetrics.icon)
            .opacity(isLaunching && pulse ? 0.45 : 1)
            .padding(.horizontal, 3)
        .frame(maxHeight: .infinity)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(background)))
        .overlay(alignment: .bottom) { indicator }
        .contentShape(Capsule())
        .onTapGesture(perform: open)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            FileDrop.load(providers) { dock.open($0, with: item) }
            return true
        }
        .contextMenu { AppMenu(item: item, dock: dock, open: open) }
        .onChange(of: isLaunching) { launching in
            withAnimation(launching ? .easeInOut(duration: 0.45).repeatForever() : .default) { pulse = launching }
        }
    }

    private var background: Double {
        if isTargeted { return 0.2 }
        return item.isActive ? 0.13 : 0
    }

    /// A short line under running apps; longer for the active one.
    private var indicator: some View {
        Capsule()
            .fill(Color.white.opacity(item.isActive ? 0.9 : 0.5))
            .frame(width: item.isActive ? 14 : 4, height: 3)
            .offset(y: 4)
            .opacity(item.isRunning ? 1 : 0)
    }
}

// MARK: - Info and Trash

/// The time, plus only the devices that need attention (low or charging).
/// Clicking opens a small panel with the date and every device's battery.
struct StatusModule: View {
    let chargeState: ChargeState
    @State private var devices = DeviceBatteries.read()
    @State private var frame: CGRect = .zero
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var notable: [DeviceBattery] { devices.filter(\.needsAttention) }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(notable) { BatteryReadout(device: $0) }
            if !notable.isEmpty {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: 1, height: 20)
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute().locale(L10n.locale)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.07)))
        .contentShape(Capsule())
        .modifier(AnchorReader(frame: $frame))
        .onTapGesture {
            reload()
            DockPopover.shared.toggle(id: "status", anchor: frame) { StatusDetails(devices: devices) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notable.map(\.id))
        .onReceive(timer) { _ in reload() }
        .onChange(of: chargeState) { _ in reload() }
    }

    private func reload() {
        let new = DeviceBatteries.read()
        if new != devices { devices = new }
    }
}

/// Date (opens Calendar) and a row per device.
struct StatusDetails: View {
    let devices: [DeviceBattery]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            } label: {
                HStack {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !devices.isEmpty {
                Divider()
                ForEach(devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: device.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(device.name).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 12)
                        BatteryReadout(device: device)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

/// Device symbol and percent, with a level line underneath.
/// Low battery turns the number orange; charging shows a green bolt instead of the symbol.
struct BatteryReadout: View {
    let device: DeviceBattery

    private var isLow: Bool { device.percent <= 20 && !device.isCharging }
    private var accent: Color {
        if device.isCharging { return Theme.green }
        return isLow ? Theme.orange : .primary
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: device.isCharging ? "bolt.fill" : device.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(device.isCharging ? Theme.green : .secondary)
                Text("\(device.percent)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(isLow || device.isCharging ? accent : Color.primary.opacity(0.7))
                        .frame(width: max(2, proxy.size.width * CGFloat(device.percent) / 100))
                }
            }
            .frame(height: 2)
        }
        .fixedSize(horizontal: true, vertical: false)
        .help("\(device.name): \(device.percent)%")
        .animation(.easeOut(duration: 0.3), value: device)
    }
}

struct TrashChip: View {
    @State private var isTargeted = false

    var body: some View {
        Image(nsImage: NSImage(named: NSImage.trashEmptyName) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: StripMetrics.icon, height: StripMetrics.icon)
            .padding(3)
            .background(Circle().fill(Color.white.opacity(isTargeted ? 0.2 : 0)))
            .contentShape(Circle())
            .onTapGesture(perform: DockModel.openTrash)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                FileDrop.load(providers, completion: DockModel.moveToTrash)
                return true
            }
            .help(L10n.dockTrash)
    }
}

struct ModuleDivider: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 3)
    }
}

private struct ChipFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// "web finished" — takes the apps' place for a few seconds. Click opens the session's terminal.
struct FinishedBanner: View {
    let session: AgentSessionInfo
    let open: () -> Void

    private var title: String { session.name ?? session.host?.folder ?? L10n.agentSession }
    private var place: String {
        [session.host?.machine ?? L10n.agentThisMac, session.name != nil ? session.host?.folder : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.green))
            Text(L10n.agentFinished(title))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(place)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule(style: .continuous).fill(LinearGradient(
            colors: [Theme.green.opacity(0.28), Theme.green.opacity(0.08)], startPoint: .leading, endPoint: .trailing
        )))
        .contentShape(Capsule())
        .onTapGesture(perform: open)
    }
}
