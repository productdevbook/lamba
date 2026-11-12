import LambaCore
import SwiftUI

enum Theme {
    static let green = Color(red: 0.24, green: 0.86, blue: 0.45)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.10)
    static let off = Color(white: 0.35)
    static let cardBackground = Color.primary.opacity(0.05)

    static func color(for phase: PomodoroPhase) -> Color {
        phase.isBreak ? green : orange
    }
}

/// How a light mode looks over time, used by the preview and swatches.
struct LightAppearance {
    let mode: LightMode

    /// Color shown at a given moment; `nil` means "unlit".
    func color(at date: Date) -> Color? {
        let t = date.timeIntervalSinceReferenceDate
        switch mode {
        case .solid(.green): return Theme.green
        case .solid(.orange): return Theme.orange
        case .solid(.off): return nil
        case .solid(.system): return nil // drawn as "automatic" by views, see isAutomatic
        case .solid(.orangeBlinkSlow): return blink(t, period: 2.0) ? Theme.orange : nil
        case .solid(.orangeBlinkFast): return blink(t, period: 0.5) ? Theme.orange : nil
        case let .pattern(pattern):
            let cycle = pattern.steps.reduce(0) { $0 + $1.duration }
            var offset = t.truncatingRemainder(dividingBy: cycle)
            for step in pattern.steps {
                if offset < step.duration { return LightAppearance(mode: .solid(step.state)).color(at: date) }
                offset -= step.duration
            }
            return nil
        }
    }

    var isAnimated: Bool {
        switch mode {
        case .solid(.orangeBlinkSlow), .solid(.orangeBlinkFast), .pattern: return true
        default: return false
        }
    }

    var isAutomatic: Bool { mode == .solid(.system) }

    private func blink(_ t: TimeInterval, period: TimeInterval) -> Bool {
        t.truncatingRemainder(dividingBy: period) < period / 2
    }
}
