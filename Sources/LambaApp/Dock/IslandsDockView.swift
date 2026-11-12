import AppKit
import Combine
import LambaCore
import SwiftUI

extension L10n {
    static func islandContext(_ name: String) -> String { format("islands.context", name) }
    static let islandContextHelp = tr("islands.contextHelp")
    static let islandTime = tr("islands.time")
    static let islandDevices = tr("islands.devices")
}

enum IslandMetrics {
    static let height: CGFloat = 52
    static let radius: CGFloat = 16
    static let gap: CGFloat = 10
    static let tile: CGFloat = 40
}

/// The v3 "Islands" Dock: separate floating islands in a bottom-aligned row.
///
/// `[ time ] [ Claude ] [ live ] [ context · apps ] [ shelf · toggles · trash ]`
///
/// Unlike the strip it follows the system appearance, and each island grows on its own.
struct IslandsDockView: View {
    @ObservedObject var dock: DockModel
    @ObservedObject var model: AppModel
    @ObservedObject var layout: DockLayout
    @ObservedObject var contexts: ContextEngine
    let shelf: ShelfModel
    let toggles: QuickToggles
    @ObservedObject var meetings: MeetingMonitor
    @ObservedObject var nowPlaying: NowPlayingMonitor

    @StateObject private var windowCounts = WindowCounts()
    @State private var launching: Set<String> = []
    /// Tile frames in window coordinates. Hover comes from the Dock's own pointer tracking
    /// because SwiftUI hover doesn't fire while Lamba isn't the active app.
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var dwell: Task<Void, Never>?
    @State private var windowListFor: String?
    @AppStorage(Preferences.Key.dockDownloads) private var showDownloads = true

    private var hovered: String? {
        guard let x = layout.pointerX else { return nil }
        return tileFrames.first { $0.value.minX <= x && x <= $0.value.maxX }?.key
    }

    private var tint: Color? {
        guard let context = contexts.current, context.look.tintDock else { return nil }
        return Color(nsColor: context.color.color)
    }

    /// The current context's apps; without a context, the plain pinned and running apps.
    private var appItems: [DockItem] {
        guard let context = contexts.current else { return dock.pinned + dock.others }
        return dock.items(forPaths: context.appPaths, includeOtherRunning: context.showOtherRunningApps)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: IslandMetrics.gap) {
            ClockPill(model: model)
            AgentBubble(model: model)
            if LiveItems.hasContent(model: model, meetings: meetings, nowPlaying: nowPlaying) {
                HStack(spacing: 6) { LiveItems(model: model, meetings: meetings, nowPlaying: nowPlaying) }
                    .modifier(IslandBackground(tint: tint))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            appsIsland
            HStack(spacing: 4) {
                ShelfTile(shelf: shelf)
                if showDownloads { DownloadsTile() }
                QuickTogglesButton(toggles: toggles)
                TrashChip()
            }
            .modifier(IslandBackground(tint: tint))
            .shelfDropTarget(shelf)
        }
        .reportFrame(to: layout)
        .padding(.bottom, StripMetrics.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: LiveItems.hasContent(model: model, meetings: meetings, nowPlaying: nowPlaying))
        .animation(.easeInOut(duration: 0.3), value: contexts.current?.id)
        .onPreferenceChange(TileFrames.self) { tileFrames = $0 }
        .onChange(of: appItems.filter(\.isRunning).map(\.path)) { running in
            launching.subtract(running)
        }
        .onChange(of: hovered) { hoverChanged(to: $0) }
        .onAppear { windowCounts.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in windowCounts.refresh() }
        // `objectWillChange` fires before the new state is set, so look one turn later.
        .onReceive(dock.objectWillChange.receive(on: DispatchQueue.main)) { windowCounts.refresh() }
    }

    // MARK: Apps island

    private var appsIsland: some View {
        let items = appItems
        let listed = Set(contexts.current?.appPaths ?? [])
        let splitIndex = contexts.current == nil ? nil : items.firstIndex { !listed.contains($0.path) }
        return HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index == splitIndex, index > 0 { islandDivider }
                tile(for: item)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: items.map(\.id))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: items.map(\.isActive))
        // While a session's finish is announced, the island's content steps aside and its space
        // becomes the notification, like in the strip.
        .opacity(model.announcement == nil ? 1 : 0)
        .scaleEffect(model.announcement == nil ? 1 : 0.96)
        .allowsHitTesting(model.announcement == nil)
        .frame(minWidth: model.announcement == nil ? 0 : 320)
        .overlay {
            if let session = model.announcement {
                FinishedBanner(session: session) {
                    model.dismissAnnouncement()
                    model.showAgent(session)
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.announcement?.id)
        .modifier(IslandBackground(tint: tint))
    }

    private var islandDivider: some View {
        Capsule().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 24).padding(.horizontal, 2)
    }

    private func tile(for item: DockItem) -> some View {
        IslandTile(
            item: item,
            isLaunching: launching.contains(item.path),
            windows: windowCounts.counts[item.path] ?? 0,
            dock: dock,
            open: {
                dwell?.cancel()
                closeWindowList()
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
                    .offset(y: -36)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .allowsHitTesting(false)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TileFrames.self, value: [item.id: proxy.frame(in: .global)])
        })
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    // MARK: Window list

    /// Resting on an app with two or more windows for a moment lists them above it.
    private func hoverChanged(to id: String?) {
        dwell?.cancel()
        // Moving to another app replaces the list; leaving the Dock keeps it so the pointer can
        // travel up into it.
        if id != nil, id != windowListFor { closeWindowList() }
        guard let id, let item = appItems.first(where: { $0.id == id }) else { return }
        guard (windowCounts.counts[item.path] ?? 0) >= 2, !DockPopover.shared.isShown else { return }
        dwell = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, hovered == id, !DockPopover.shared.isShown else { return }
            openWindowList(for: item)
        }
    }

    private func openWindowList(for item: DockItem) {
        guard let anchor = tileFrames[item.id] else { return }
        let windows = WindowList.windows(of: item)
        let count = windowCounts.counts[item.path] ?? 0
        windowListFor = item.id
        DockPopover.shared.toggle(id: "windows-\(item.id)", anchor: anchor) {
            WindowListPopover(item: item, windows: windows, count: count) { window in
                DockPopover.shared.close()
                WindowList.raise(window, of: item)
            }
        }
    }

    private func closeWindowList() {
        guard windowListFor != nil else { return }
        windowListFor = nil
        DockPopover.shared.close()
    }
}

// MARK: - Island chrome

/// Height, radius, blur, hairline and shadow of an island; optionally washed with the context color.
private struct IslandBackground: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: IslandMetrics.radius, style: .continuous)
        content
            .padding(.horizontal, 6)
            .padding(.vertical, (IslandMetrics.height - IslandMetrics.tile) / 2)
            .frame(height: IslandMetrics.height)
            .background {
                ZStack {
                    VisualEffect(material: .popover).clipShape(shape)
                    if let tint { shape.fill(tint.opacity(0.1)) }
                    shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            }
    }
}

private struct TileFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Time island

/// One small pill: the Lamba module (LED / Pomodoro), Claude, and the time. Battery shows only when it matters (low, or a low accessory).
/// Click the LED to start/pause Pomodoro; click the time for date, batteries and devices.
/// The clock is the Pomodoro: tap it to start a focus session; while one runs the same pill
/// shows the time left with a progress ring around the light (tap to pause, right-click for more).
private struct ClockPill: View {
    @ObservedObject var model: AppModel
    @State private var devices = DeviceBatteries.read()
    @State private var frame: CGRect = .zero
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var lowBattery: DeviceBattery? {
        devices.first { $0.kind == .mac && $0.isLow } ?? devices.first { $0.kind != .mac && $0.isLow }
    }

    private var phaseColor: Color? {
        model.pomodoro.map { Theme.color(for: $0.phase) }
    }

    var body: some View {
        HStack(spacing: 9) {
            ring
            TimelineView(.periodic(from: .now, by: 15)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pomodoro = model.pomodoro {
                        Text(pomodoro.formattedRemaining)
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(pomodoro.isPaused ? .secondary : .primary)
                        Text(clock(at: context.date))
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(clock(at: context.date))
                            .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                }
            }
            if let lowBattery {
                Text("\(lowBattery.percent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.orange)
                    .accessibilityLabel("\(lowBattery.name): \(lowBattery.percent)%")
            }
        }
        .lineLimit(1)
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: IslandMetrics.height)
        .background { GlassShape(shape: Capsule(style: .continuous), tint: phaseColor) }
        .contentShape(Capsule())
        .modifier(AnchorReader(frame: $frame))
        .onTapGesture(perform: model.togglePomodoro)
        .contextMenu {
            LambaMenu(model: model)
            Divider()
            Button(L10n.islandDevices) {
                reload()
                DockPopover.shared.toggle(id: "status", anchor: frame) { StatusDetails(devices: devices) }
            }
        }
        .help(model.pomodoro == nil ? L10n.pomodoroStartMenu : L10n.dockLambaHelp)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.islandTime)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.pomodoro == nil)
        .animation(.easeInOut(duration: 0.25), value: model.pomodoro?.isPaused)
        .onReceive(timer) { _ in reload() }
        .onChange(of: model.chargeState) { _ in reload() }
    }

    /// The MagSafe light in the middle; a Pomodoro draws its progress around it.
    private var ring: some View {
        ZStack {
            Circle().strokeBorder(Color.primary.opacity(model.pomodoro == nil ? 0 : 0.12), lineWidth: 2.5)
            if let pomodoro = model.pomodoro, let color = phaseColor {
                Circle()
                    .trim(from: 0, to: model.pomodoroProgress)
                    .stroke(color.opacity(pomodoro.isPaused ? 0.45 : 1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.25)
                    .animation(.linear(duration: 1), value: model.pomodoroProgress)
                if pomodoro.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                } else {
                    LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 9)
                }
            } else {
                LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: 10)
            }
        }
        .frame(width: 24, height: 24)
    }

    /// The time, following the system's 12/24-hour setting.
    private func clock(at date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func reload() {
        let new = DeviceBatteries.read()
        if new != devices { devices = new }
    }
}

/// Claude in its own small round bubble next to the clock.
private struct AgentBubble: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AgentIcon(model: model)
            .frame(width: 40, height: 40)
            .frame(width: IslandMetrics.height, height: IslandMetrics.height)
            .background { GlassShape(shape: Circle(), tint: nil) }
    }
}

/// The frosted look of the islands, for any shape.
private struct GlassShape<S: InsettableShape>: View {
    let shape: S
    let tint: Color?

    var body: some View {
        ZStack {
            VisualEffect(material: .popover).clipShape(shape)
            if let tint { shape.fill(tint.opacity(0.14)) }
            shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

/// "82%" with a level glyph; orange when low, a green bolt while charging.
private struct MacBattery: View {
    let device: DeviceBattery

    private var symbol: String {
        if device.isCharging { return "battery.100.bolt" }
        switch device.percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var accent: Color {
        if device.isCharging { return Theme.green }
        return device.isLow ? Theme.orange : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(accent)
            Text("\(device.percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(device.isLow ? Theme.orange : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name): \(device.percent)%")
    }
}

/// An app icon with one small bar per open window beneath it.
private struct IslandTile: View {
    let item: DockItem
    let isLaunching: Bool
    let windows: Int
    @ObservedObject var dock: DockModel
    let open: () -> Void

    @State private var isTargeted = false
    @State private var pulse = false

    var body: some View {
        Image(nsImage: item.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: IslandMetrics.tile, height: IslandMetrics.tile)
            .opacity(isLaunching && pulse ? 0.45 : 1)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(isTargeted ? 0.18 : item.isActive ? 0.1 : 0)))
            .overlay(alignment: .bottom) { windowBars }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                FileDrop.load(providers) { dock.open($0, with: item) }
                return true
            }
            .contextMenu { AppMenu(item: item, dock: dock, open: open) }
            .onChange(of: isLaunching) { launching in
                withAnimation(launching ? .easeInOut(duration: 0.45).repeatForever() : .default) { pulse = launching }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.name)
    }

    /// 6×2 bars, at most four; they sit in the island's bottom padding.
    private var windowBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<min(windows, 4), id: \.self) { _ in
                Capsule()
                    .fill(Color.primary.opacity(item.isActive ? 0.85 : 0.55))
                    .frame(width: 6, height: 2)
            }
        }
        .offset(y: 5)
        .animation(.easeOut(duration: 0.2), value: windows)
    }
}
