import Foundation

/// One entry in the local activity log. Everything stays on this Mac; nothing is sent anywhere.
public struct ActivityRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Time spent in a Pomodoro work phase. `value` is `completed` or `partial`.
        case focus
        /// How long a light mode was active. `value` is the mode name (e.g. `green`, `alternate`).
        case light
        /// How long the charger was in a state. `value` is a `ChargeState` name.
        case charge
        /// A notification flash (instant). `value` is the color.
        case flash
    }

    public static let completed = "completed"
    public static let partial = "partial"

    public var kind: Kind
    public var start: Date
    public var end: Date
    public var value: String

    public init(kind: Kind, start: Date, end: Date, value: String) {
        self.kind = kind
        self.start = start
        self.end = max(start, end)
        self.value = value
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Seconds of this record that fall inside `interval`.
    public func overlap(with interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }
}

extension ChargeState {
    public var name: String {
        switch self {
        case .onBattery: return "battery"
        case .charging: return "charging"
        case .notCharging: return "plugged"
        }
    }
}
