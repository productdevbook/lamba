/// What the charger is doing; decides the LED color while macOS controls it.
public enum ChargeState: Equatable, Sendable {
    case onBattery
    case charging
    case notCharging // plugged in and full, or charging paused

    /// The LED color macOS shows in this state (amber while charging, green otherwise, dark on battery).
    public var systemLight: LightState {
        switch self {
        case .onBattery: return .off
        case .charging: return .orange
        case .notCharging: return .green
        }
    }
}

extension LightState {
    /// The state actually visible on the LED, replacing `.system` with what macOS shows.
    public func resolved(for charge: ChargeState) -> LightState {
        self == .system ? charge.systemLight : self
    }
}
