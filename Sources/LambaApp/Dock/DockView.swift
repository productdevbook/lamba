import AppKit
import LambaCore
import SwiftUI

/// Size and pointer state shared between the Dock window and its SwiftUI content.
enum DockStyle: String, CaseIterable, Identifiable {
    /// v3: separate floating islands (time, Claude, the context's apps, shelf and toggles).
    case islands
    /// A long, floating strip of modules: Lamba status, app chips that unfold into names, clock and battery.
    case strip
    /// Icons with hover magnification, like the macOS Dock.
    case classic

    var id: String { rawValue }
}

final class DockLayout: ObservableObject {
    @Published var style: DockStyle = .strip
    @Published var iconSize: CGFloat = 48
    @Published var magnification: CGFloat = 1.6
    /// Pointer x in the window's coordinates while it is over the bar; `nil` otherwise.
    @Published var pointerX: CGFloat?
    /// Window width, used to map the pointer onto the unmagnified layout.
    @Published var width: CGFloat = 0

    var padding: CGFloat { (iconSize * 0.12).rounded() }
    var spacing: CGFloat { (iconSize * 0.08).rounded() }
    var barHeight: CGFloat { iconSize + padding * 2 }
    /// The bar's frame in window coordinates (origin bottom-left), reported by the view.
    var barFrame: CGRect = .zero

    /// Room above the bar for magnified icons and the name label.
    var windowHeight: CGFloat {
        switch style {
        case .strip, .islands: return StripMetrics.height + StripMetrics.bottomMargin + 40
        case .classic: return iconSize * max(magnification, 1) + padding * 2 + 34
        }
    }

    func baseWidth(of slot: DockSlot) -> CGFloat {
        slot.isSeparator ? 1 + spacing * 2 : iconSize
    }

    /// Width of the bar when nothing is magnified.
    func baseWidth(of slots: [DockSlot]) -> CGFloat {
        slots.map(baseWidth(of:)).reduce(0, +) + spacing * CGFloat(max(slots.count - 1, 0)) + padding * 2
    }
}

extension DockModel {
    /// Pinned apps, other running apps, then Lamba and the Trash.
    var slots: [DockSlot] {
        var slots = pinned.map(DockSlot.app)
        if !others.isEmpty {
            slots.append(.separator("apps"))
            slots += others.map(DockSlot.app)
        }
        slots += [.separator("extras"), .lamba, .trash]
        return slots
    }
}

/// One position in the Dock.
enum DockSlot: Identifiable {
    case app(DockItem)
    case separator(String)
    case lamba
    case trash

    var id: String {
        switch self {
        case let .app(item): return item.id
        case let .separator(id): return "separator." + id
        case .lamba: return "lamba"
        case .trash: return "trash"
        }
    }

    var isSeparator: Bool {
        if case .separator = self { return true }
        return false
    }
}

struct ClassicDockView: View {
    @ObservedObject var dock: DockModel
    @ObservedObject var layout: DockLayout
    @ObservedObject var model: AppModel

    @State private var launching: Set<String> = []

    var body: some View {
        let slots = dock.slots
        let scales = Magnifier(layout: layout, slots: slots).scales()
        let hovered = scales.firstIndex { $0 == scales.max() && $0 > 1.001 }

        HStack(alignment: .bottom, spacing: layout.spacing) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                tile(for: slot, scale: scales[index], showsLabel: index == hovered)
            }
        }
        .padding(.horizontal, layout.padding)
        .padding(.bottom, layout.padding)
        .background(alignment: .bottom) { bar.reportFrame(to: layout) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: layout.pointerX)
        .animation(.easeOut(duration: 0.2), value: slots.map(\.id))
        .onChange(of: dock.others.map(\.isRunning) + dock.pinned.map(\.isRunning)) { _ in
            let running = Set((dock.pinned + dock.others).filter(\.isRunning).map(\.path))
            launching.subtract(running)
        }
    }

    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: layout.iconSize * 0.36, style: .continuous)
        return VisualEffect()
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .overlay(alignment: .top) { glow.clipShape(shape) }
            .frame(height: layout.barHeight)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    /// A thin line along the top edge in the color the LED shows right now.
    private var glow: some View {
        LinearGradient(
            colors: [.clear, ledColor.opacity(0.9), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.5)
        .padding(.horizontal, layout.iconSize * 0.5)
    }

    private var ledColor: Color {
        switch model.visibleLight {
        case .green: return Theme.green
        case .orange, .orangeBlinkSlow, .orangeBlinkFast: return Theme.orange
        case .off, .system: return .clear
        }
    }

    @ViewBuilder
    private func tile(for slot: DockSlot, scale: CGFloat, showsLabel: Bool) -> some View {
        let size = layout.iconSize * scale
        switch slot {
        case let .app(item):
            AppTile(item: item, size: size, isLaunching: launching.contains(item.path), dock: dock) {
                if !item.isRunning { launching.insert(item.path) }
                dock.open(item)
            }
            .overlay(alignment: .top) { if showsLabel { NameLabel(text: item.name).offset(y: -30) } }
        case .separator:
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 1, height: layout.iconSize * 0.75)
                .padding(.horizontal, layout.spacing)
                .padding(.bottom, layout.iconSize * 0.125)
        case .lamba:
            LambaTile(model: model, size: size)
                .overlay(alignment: .top) { if showsLabel { NameLabel(text: L10n.appName).offset(y: -30) } }
        case .trash:
            TrashTile(size: size)
                .overlay(alignment: .top) { if showsLabel { NameLabel(text: L10n.dockTrash).offset(y: -30) } }
        }
    }
}

// MARK: - Magnification

/// Scales icons near the pointer with a cosine falloff, measured on the unmagnified layout
/// so icons don't run away from the pointer while the bar grows.
private struct Magnifier {
    let layout: DockLayout
    let slots: [DockSlot]

    func scales() -> [CGFloat] {
        guard let pointer = layout.pointerX, layout.magnification > 1.01 else {
            return Array(repeating: 1, count: slots.count)
        }
        let widths = slots.map(layout.baseWidth(of:))
        var x = (layout.width - layout.baseWidth(of: slots)) / 2 + layout.padding
        let radius = layout.iconSize * 2.5

        return zip(slots, widths).map { slot, width in
            defer { x += width + layout.spacing }
            guard !slot.isSeparator else { return 1 }
            let distance = abs(pointer - (x + width / 2))
            guard distance < radius else { return 1 }
            let falloff = (cos(.pi * distance / radius) + 1) / 2
            return 1 + (layout.magnification - 1) * falloff
        }
    }
}

// MARK: - Tiles

private struct AppTile: View {
    let item: DockItem
    let size: CGFloat
    let isLaunching: Bool
    @ObservedObject var dock: DockModel
    let open: () -> Void

    @State private var bounce = false
    @State private var isTargeted = false

    var body: some View {
        Image(nsImage: item.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .brightness(isTargeted ? 0.15 : 0)
            .offset(y: bounce ? -size * 0.35 : 0)
            .overlay(alignment: .bottom) { RunningDot(isVisible: item.isRunning).offset(y: dotOffset) }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                FileDrop.load(providers) { dock.open($0, with: item) }
                return true
            }
            .contextMenu { AppMenu(item: item, dock: dock, open: open) }
            .onChange(of: isLaunching) { launching in
                withAnimation(launching ? .easeInOut(duration: 0.35).repeatForever() : .easeOut(duration: 0.2)) {
                    bounce = launching
                }
            }
    }

    // Sits in the bar's bottom padding.
    private var dotOffset: CGFloat { 4 }

}

/// Right-click menu of an app in either Dock style.
struct AppMenu: View {
    let item: DockItem
    @ObservedObject var dock: DockModel
    let open: () -> Void

    var body: some View {
        Button(item.isRunning ? L10n.dockShow : L10n.dockOpen, action: open)
        Button(L10n.dockShowInFinder) { dock.showInFinder(item) }
        Divider()
        if item.isPinned {
            if item.path != AppleDock.finderPath {
                Button(L10n.dockMoveLeft) { dock.move(item, by: -1) }
                Button(L10n.dockMoveRight) { dock.move(item, by: 1) }
                Button(L10n.dockRemove) { dock.unpin(item) }
            }
        } else {
            Button(L10n.dockKeep) { dock.pin(item) }
        }
        if item.isRunning {
            Divider()
            Button(L10n.dockHide) { dock.hide(item) }
            Button(L10n.dockQuit) { dock.quit(item) }
        }
    }
}

private struct RunningDot: View {
    let isVisible: Bool

    var body: some View {
        Circle()
            .fill(Color.primary.opacity(isVisible ? 0.75 : 0))
            .frame(width: 4, height: 4)
    }
}

/// Lamba's own tile: the LED orb, wrapped in the Pomodoro ring while a session runs.
private struct LambaTile: View {
    @ObservedObject var model: AppModel
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                .padding(size * 0.06)
            if let pomodoro = model.pomodoro {
                ProgressRing(progress: model.pomodoroProgress, color: Theme.color(for: pomodoro.phase), isPaused: pomodoro.isPaused)
                    .padding(size * 0.16)
                Text(pomodoro.formattedRemaining)
                    .font(.system(size: size * 0.2, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(pomodoro.isPaused ? 0.5 : 0.95))
            } else {
                LEDView(appearance: LightAppearance(mode: .solid(model.visibleLight)), size: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .contextMenu { LambaMenu(model: model) }
        .help(L10n.dockLambaHelp)
    }

    private func toggle() { model.togglePomodoro() }
}

/// Right-click menu of the Lamba tile/module: Pomodoro controls and light modes.
struct LambaMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let pomodoro = model.pomodoro {
            Button(pomodoro.isPaused ? L10n.pomodoroResume : L10n.pomodoroPause, action: model.togglePomodoro)
            Button(L10n.pomodoroSkip, action: model.skipPomodoro)
            Button(L10n.pomodoroStop, action: model.stopPomodoro)
        } else {
            Button(L10n.pomodoroStartMenu, action: model.startPomodoro)
        }
        if model.isSupported {
            Divider()
            ForEach(Self.lights, id: \.1) { mode, title in
                Button(title) { model.select(mode) }
            }
        }
        Divider()
        Button(L10n.statistics + "…", action: model.openStatistics)
        Button(L10n.settings + "…", action: model.openSettings)
    }

    private static let lights: [(LightMode, String)] = [
        (.solid(.green), L10n.green),
        (.solid(.orange), L10n.orange),
        (.solid(.off), L10n.off),
        (.solid(.orangeBlinkSlow), L10n.modeTitle(.solid(.orangeBlinkSlow))),
        (.pattern(.alternate), L10n.modeTitle(.pattern(.alternate))),
        (.solid(.system), L10n.automatic),
    ]
}

private struct TrashTile: View {
    let size: CGFloat
    @State private var isTargeted = false
    @State private var isFull = TrashTile.trashHasItems()

    var body: some View {
        Image(nsImage: NSImage(named: isFull ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .brightness(isTargeted ? 0.15 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: DockModel.openTrash)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                FileDrop.load(providers) { files in
                    DockModel.moveToTrash(files)
                    isFull = true
                }
                return true
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
                isFull = Self.trashHasItems()
            }
    }

    /// Reading ~/.Trash can be denied by privacy settings; then the empty icon is shown.
    private static func trashHasItems() -> Bool {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        return items.contains { $0 != ".DS_Store" }
    }
}

struct NameLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

/// Collects file URLs from a drop, then calls back on the main queue.
enum FileDrop {
    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { completion(urls) }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Picks the view for the chosen Dock style.
struct DockRootView: View {
    @ObservedObject var dock: DockModel
    @ObservedObject var layout: DockLayout
    @ObservedObject var model: AppModel
    let contexts: ContextEngine
    let shelf: ShelfModel
    let toggles: QuickToggles
    let meetings: MeetingMonitor
    let nowPlaying: NowPlayingMonitor

    var body: some View {
        switch layout.style {
        case .islands: IslandsDockView(dock: dock, model: model, layout: layout, contexts: contexts, shelf: shelf, toggles: toggles, meetings: meetings, nowPlaying: nowPlaying)
        case .strip: StripDockView(dock: dock, model: model, layout: layout, meetings: meetings, nowPlaying: nowPlaying)
        case .classic: ClassicDockView(dock: dock, layout: layout, model: model)
        }
    }
}

extension View {
    /// Stores this view's frame, converted to window coordinates (origin bottom-left), in the layout.
    func reportFrame(to layout: DockLayout) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { layout.store(frame) }
                .onChange(of: frame) { layout.store($0) }
        })
    }
}

extension DockLayout {
    fileprivate func store(_ global: CGRect) {
        barFrame = windowRect(global)
    }

    private func windowRect(_ global: CGRect) -> CGRect {
        CGRect(x: global.minX, y: windowHeight - global.maxY, width: global.width, height: global.height)
    }
}
