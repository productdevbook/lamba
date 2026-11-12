import Foundation

/// A Dock context ("Work", "Personal", "Presenting"): its own apps, and how the Mac looks while
/// it is active. Contexts switch by hand or by rules (time, display, Wi-Fi, front app, mirroring).
public struct DockContext: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: ContextColor
    /// App bundle paths shown in the Dock's app island, in order.
    public var appPaths: [String]
    /// Also show running apps that aren't in `appPaths`.
    public var showOtherRunningApps: Bool
    /// Rules that switch to this context. Earlier contexts in the list win when several match.
    public var rules: [ContextRule]
    public var look: ContextLook

    public init(
        id: UUID = UUID(), name: String, color: ContextColor, appPaths: [String] = [],
        showOtherRunningApps: Bool = true, rules: [ContextRule] = [], look: ContextLook = ContextLook()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.appPaths = appPaths
        self.showOtherRunningApps = showOtherRunningApps
        self.rules = rules
        self.look = look
    }
}

public enum ContextColor: String, Codable, CaseIterable, Sendable {
    case blue, pink, green, orange, purple, gray

    /// sRGB components, 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: return (0.231, 0.510, 0.965)
        case .pink: return (0.878, 0.271, 0.482)
        case .green: return (0.086, 0.639, 0.290)
        case .orange: return (0.961, 0.620, 0.043)
        case .purple: return (0.545, 0.361, 0.965)
        case .gray: return (0.420, 0.447, 0.502)
        }
    }
}

public struct ContextRule: Codable, Hashable, Identifiable, Sendable {
    public enum Trigger: Codable, Hashable, Sendable {
        /// On these weekdays (1 = Sunday … 7 = Saturday, as `Calendar`), between two times given in
        /// minutes after midnight. An end before the start spans midnight.
        case schedule(weekdays: Set<Int>, startMinute: Int, endMinute: Int)
        /// While a display with this name is connected.
        case display(name: String)
        /// While on this Wi-Fi network.
        case wifi(ssid: String)
        /// While this app is frontmost.
        case frontApp(bundleID: String)
        /// While a display is mirrored (projector, AirPlay mirroring).
        case mirroring
    }

    public var id: UUID
    public var isEnabled: Bool
    public var trigger: Trigger

    public init(id: UUID = UUID(), isEnabled: Bool = true, trigger: Trigger) {
        self.id = id
        self.isEnabled = isEnabled
        self.trigger = trigger
    }

    public func matches(_ environment: ContextEnvironment) -> Bool {
        guard isEnabled else { return false }
        switch trigger {
        case let .schedule(weekdays, start, end):
            let parts = environment.calendar.dateComponents([.weekday, .hour, .minute], from: environment.date)
            guard let weekday = parts.weekday, weekdays.contains(weekday) else { return false }
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if start == end { return true }
            return start < end ? (start <= minute && minute < end) : (minute >= start || minute < end)
        case let .display(name):
            return environment.displayNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
        case let .wifi(ssid):
            return environment.wifiSSID == ssid
        case let .frontApp(bundleID):
            return environment.frontBundleID == bundleID
        case .mirroring:
            return environment.isMirroring
        }
    }
}

/// What changes on the Mac when a context becomes active. `nil` means "leave as it is".
public struct ContextLook: Codable, Hashable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable { case light, dark }

    /// A file path, or `builtin:<id>` for one of Lamba's wallpapers.
    public var wallpaper: String?
    public var appearance: Appearance?
    /// Tint the Dock islands with the context color.
    public var tintDock: Bool
    /// Flash the MagSafe LED in this color when switching (green, orange); `nil`: no flash.
    public var flashColor: LightState?
    /// Name of a Shortcuts shortcut to run (e.g. one that turns a Focus on).
    public var shortcut: String?
    public var openApps: [String]
    public var hideApps: [String]

    public init(
        wallpaper: String? = nil, appearance: Appearance? = nil, tintDock: Bool = true,
        flashColor: LightState? = nil, shortcut: String? = nil, openApps: [String] = [], hideApps: [String] = []
    ) {
        self.wallpaper = wallpaper
        self.appearance = appearance
        self.tintDock = tintDock
        self.flashColor = flashColor
        self.shortcut = shortcut
        self.openApps = openApps
        self.hideApps = hideApps
    }
}

/// The facts rules are checked against.
public struct ContextEnvironment: Equatable, Sendable {
    public var date: Date
    public var calendar: Calendar
    public var displayNames: [String]
    public var wifiSSID: String?
    public var frontBundleID: String?
    public var isMirroring: Bool

    public init(
        date: Date = Date(), calendar: Calendar = .current, displayNames: [String] = [],
        wifiSSID: String? = nil, frontBundleID: String? = nil, isMirroring: Bool = false
    ) {
        self.date = date
        self.calendar = calendar
        self.displayNames = displayNames
        self.wifiSSID = wifiSSID
        self.frontBundleID = frontBundleID
        self.isMirroring = isMirroring
    }
}

public enum ContextResolver {
    /// The first context, in list order, with an enabled rule that matches.
    public static func match(_ contexts: [DockContext], in environment: ContextEnvironment) -> UUID? {
        contexts.first { $0.rules.contains { $0.matches(environment) } }?.id
    }
}

/// Which context is active. A hand-picked context stays until the rules' answer changes
/// (e.g. the next morning, or a display is connected); then the rules take over again.
public struct ContextSelection: Equatable, Sendable {
    public private(set) var manual: UUID?
    public private(set) var matched: UUID?

    public init() {}

    public mutating func choose(_ id: UUID) {
        manual = id
    }

    /// Feeds the rules' current answer; returns the active context.
    @discardableResult
    public mutating func update(matched newMatch: UUID?, fallback: UUID?) -> UUID? {
        if newMatch != matched {
            matched = newMatch
            manual = nil
        }
        return active(fallback: fallback)
    }

    public func active(fallback: UUID?) -> UUID? {
        manual ?? matched ?? fallback
    }
}
