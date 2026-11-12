import Foundation

/// A timed sequence of LED states, played by the app.
public struct LightPattern: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var state: LightState
        public var duration: TimeInterval

        public init(_ state: LightState, _ duration: TimeInterval) {
            self.state = state
            self.duration = duration
        }
    }

    public var name: String
    public var steps: [Step]
    /// How many times the steps run; `nil` loops until replaced.
    public var repeats: Int?

    public init(name: String, steps: [Step], repeats: Int?) {
        precondition(!steps.isEmpty, "A pattern needs at least one step")
        self.name = name
        self.steps = steps
        self.repeats = repeats.map { max(1, $0) }
    }

    /// Total play time, or `nil` for endless patterns.
    public var duration: TimeInterval? {
        repeats.map { Double($0) * steps.reduce(0) { $0 + $1.duration } }
    }

    /// Green and orange taking turns, forever.
    public static let alternate = LightPattern(
        name: "alternate",
        steps: [Step(.green, 0.5), Step(.orange, 0.5)],
        repeats: nil
    )

    public static let maxFlashCount = 20

    /// Short on/off blinks used for notifications; ends with the LED off.
    public static func flash(_ color: LightState, times: Int) -> LightPattern {
        LightPattern(
            name: "flash-\(color.rawValue)",
            steps: [Step(color, 0.25), Step(.off, 0.25)],
            repeats: min(max(times, 1), maxFlashCount)
        )
    }
}
