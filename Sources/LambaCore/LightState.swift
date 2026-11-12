/// A state the MagSafe 3 LED can be put in by the hardware.
///
/// These map to the undocumented SMC key `ACLC`. The set is a whitelist:
/// the helper refuses any value that is not one of these cases.
public enum LightState: String, Codable, CaseIterable, Sendable {
    /// macOS controls the LED (amber while charging, green when full).
    case system
    case off
    case green
    case orange
    case orangeBlinkSlow = "orange-blink-slow"
    case orangeBlinkFast = "orange-blink-fast"

    public var smcValue: UInt8 {
        switch self {
        case .system: return 0
        case .off: return 1
        case .green: return 3
        case .orange: return 4
        case .orangeBlinkSlow: return 6
        case .orangeBlinkFast: return 7
        }
    }

    public init?(smcValue: UInt8) {
        guard let match = Self.allCases.first(where: { $0.smcValue == smcValue }) else { return nil }
        self = match
    }

    /// Colors that can be used for short notification flashes.
    public static let flashColors: [LightState] = [.green, .orange]
}
