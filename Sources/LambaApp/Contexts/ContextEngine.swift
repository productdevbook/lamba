import AppKit
import Combine
import LambaCore

/// Owns the user's Dock contexts and decides which one is active.
///
/// Rules are re-checked on a timer and on display/front-app changes (`ContextEnvironmentMonitor`);
/// a hand-picked context wins until the rules' answer changes (`ContextSelection`). Every switch
/// applies the new context's look (`LookApplier`) and can be undone for a few seconds.
final class ContextEngine: ObservableObject {
    private enum Key {
        static let contexts = "dockContexts"
        static let defaultID = "dockDefaultContextID"
        static let appliedID = "dockAppliedContextID"
    }

    /// How long the "Undo" offer after a switch stays available.
    static let undoWindow: TimeInterval = 10

    /// All contexts, in priority order (earlier wins when several rules match).
    @Published private(set) var contexts: [DockContext] = []
    /// The active context.
    @Published private(set) var current: DockContext?
    /// Used when no rule matches and nothing was picked by hand.
    @Published private(set) var defaultID: UUID?
    /// The last switch, for the "Undo" offer shortly after it happens.
    @Published private(set) var lastSwitch: ContextSwitch?
    /// Current Wi-Fi network name, when known (for the settings' "this network" rule).
    @Published private(set) var currentSSID: String?

    /// Flashes the MagSafe LED; set by the app model.
    var flash: (LightState, Int) -> Void = { _, _ in }

    private let defaults: UserDefaults
    private let monitor = ContextEnvironmentMonitor()
    private let applier = LookApplier()
    private var selection = ContextSelection()
    private var started = false
    private var undoTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        current = contexts.first { $0.id == selection.active(fallback: defaultID) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        applier.flash = { [weak self] state, count in self?.flash(state, count) }
        monitor.onChange = { [weak self] in self?.evaluate() }
        monitor.setWiFiNeeded(usesWiFiRule)
        monitor.start()
        evaluate()
    }

    func stop() {
        started = false
        monitor.stop()
        undoTimer?.invalidate()
    }

    // MARK: - Editing

    /// Switches by hand. Stays until the rules' answer changes.
    func select(_ id: UUID) {
        guard let target = contexts.first(where: { $0.id == id }) else { return }
        selection.choose(id)
        if target.id != current?.id {
            switchTo(target, reason: nil, recordSwitch: true)
        }
    }

    /// Saves an edited context (matched by id).
    func update(_ context: DockContext) {
        guard let index = contexts.firstIndex(where: { $0.id == context.id }) else { return }
        contexts[index] = context
        if current?.id == context.id { current = context }
        save()
        monitor.setWiFiNeeded(usesWiFiRule)
        if started { evaluate() }
    }

    @discardableResult
    func add(name: String) -> DockContext {
        let used = Set(contexts.map(\.color))
        let color = ContextColor.allCases.first { !used.contains($0) } ?? .purple
        let appPaths = contexts.first(where: { $0.id == defaultID })?.appPaths ?? contexts.first?.appPaths ?? []
        let context = DockContext(name: name, color: color, appPaths: appPaths)
        contexts.append(context)
        if defaultID == nil { defaultID = context.id }
        save()
        return context
    }

    /// The last context can't be deleted. Deleting the active one switches to the fallback.
    func delete(_ id: UUID) {
        guard contexts.count > 1, contexts.contains(where: { $0.id == id }) else { return }
        contexts.removeAll { $0.id == id }
        if defaultID == id { defaultID = contexts.first?.id }
        if lastSwitch?.from == id || lastSwitch?.to == id { clearLastSwitch() }
        if selection.manual == id { selection = ContextSelection() }
        save()
        evaluate()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        contexts.move(fromOffsets: source, toOffset: destination)
        save()
        if started { evaluate() }
    }

    func setDefault(_ id: UUID) {
        guard contexts.contains(where: { $0.id == id }) else { return }
        defaultID = id
        save()
        if started { evaluate() }
    }

    // MARK: - Look

    /// Applies a context's look right now, without making it active ("Try now").
    func preview(_ id: UUID) {
        guard let context = contexts.first(where: { $0.id == id }) else { return }
        applier.apply(context.look)
        // The Mac no longer shows the active context's look; make the next launch re-apply it.
        defaults.removeObject(forKey: Key.appliedID)
    }

    /// Reverts the last switch's look and returns to the previous context.
    func undoLastSwitch() {
        guard let last = lastSwitch, let previous = contexts.first(where: { $0.id == last.from }) else {
            clearLastSwitch()
            return
        }
        clearLastSwitch()
        selection.choose(previous.id)
        switchTo(previous, reason: nil, recordSwitch: false)
    }

    // MARK: - Rules

    private var usesWiFiRule: Bool {
        contexts.contains { context in
            context.rules.contains { rule in
                if case .wifi = rule.trigger { return rule.isEnabled }
                return false
            }
        }
    }

    private func evaluate() {
        let ssid = monitor.ssid
        if ssid != currentSSID { currentSSID = ssid }
        let environment = monitor.environment()
        let matched = ContextResolver.match(contexts, in: environment)
        let fallback = defaultID ?? contexts.first?.id
        guard let activeID = selection.update(matched: matched, fallback: fallback),
              let target = contexts.first(where: { $0.id == activeID }) else { return }

        if target.id == current?.id {
            // Same context: just pick up edits, and apply at launch if the Mac isn't showing it yet.
            if current != target { current = target }
            if defaults.string(forKey: Key.appliedID) != target.id.uuidString { applyAndRemember(target) }
            return
        }
        let byRule = selection.manual == nil && matched == target.id
        let reason = byRule ? Self.reason(for: target, environment: environment) : nil
        switchTo(target, reason: reason, recordSwitch: current != nil)
    }

    private func switchTo(_ target: DockContext, reason: String?, recordSwitch: Bool) {
        let previous = current
        current = target
        applyAndRemember(target)
        if recordSwitch {
            lastSwitch = ContextSwitch(from: previous?.id, to: target.id, at: Date(), reason: reason)
            undoTimer?.invalidate()
            undoTimer = Timer.scheduledTimer(withTimeInterval: Self.undoWindow, repeats: false) { [weak self] _ in
                self?.clearLastSwitch()
            }
        }
    }

    private func clearLastSwitch() {
        undoTimer?.invalidate()
        undoTimer = nil
        if lastSwitch != nil { lastSwitch = nil }
    }

    private func applyAndRemember(_ context: DockContext) {
        applier.apply(context.look)
        defaults.set(context.id.uuidString, forKey: Key.appliedID)
    }

    // MARK: - Reason text

    private static func reason(for context: DockContext, environment: ContextEnvironment) -> String? {
        guard let rule = context.rules.first(where: { $0.matches(environment) }) else { return nil }
        let time = DateFormatter.localizedString(from: environment.date, dateStyle: .none, timeStyle: .short)
        let key: String
        switch rule.trigger {
        case .schedule: key = "ctx.reason.time"
        case .display: key = "ctx.reason.display"
        case .wifi: key = "ctx.reason.wifi"
        case .frontApp: key = "ctx.reason.app"
        case .mirroring: key = "ctx.reason.mirroring"
        }
        return L10n.format(key, time)
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Key.contexts),
           let saved = try? JSONDecoder().decode([DockContext].self, from: data), !saved.isEmpty {
            contexts = saved
            defaultID = defaults.string(forKey: Key.defaultID).flatMap(UUID.init(uuidString:))
            if !saved.contains(where: { $0.id == defaultID }) { defaultID = saved.first?.id }
        } else {
            let names = DefaultContexts.Names(work: L10n.ctxWork, personal: L10n.ctxPersonal, presenting: L10n.ctxPresenting)
            let apps = Preferences.dockPinnedPaths ?? AppleDock.pinnedAppPaths()
            let made = DefaultContexts.make(names: names, appPaths: apps)
            contexts = made.contexts
            defaultID = made.defaultID
            save()
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(contexts), forKey: Key.contexts)
        defaults.set(defaultID?.uuidString, forKey: Key.defaultID)
    }
}

struct ContextSwitch: Equatable {
    let from: UUID?
    let to: UUID
    let at: Date
    /// Why it happened, for display ("09:00 · display connected"); `nil` when picked by hand.
    let reason: String?
}

extension ContextColor {
    var color: NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension L10n {
    static let ctxWork = tr("ctx.name.work")
    static let ctxPersonal = tr("ctx.name.personal")
    static let ctxPresenting = tr("ctx.name.presenting")
}
