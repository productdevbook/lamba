import Foundation

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var workMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    public var sessionsBeforeLongBreak: Int

    public init(
        workMinutes: Double = 25,
        shortBreakMinutes: Double = 5,
        longBreakMinutes: Double = 15,
        sessionsBeforeLongBreak: Int = 4
    ) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
    }

    public func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: return workMinutes * 60
        case .shortBreak: return shortBreakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }
}

public enum PomodoroPhase: String, Codable, Sendable {
    case work
    case shortBreak = "short-break"
    case longBreak = "long-break"

    public var isBreak: Bool { self != .work }
}

public enum PomodoroAction: String, Codable, CaseIterable, Sendable {
    case start, pause, resume, stop, skip
}

public struct PomodoroSnapshot: Codable, Equatable, Sendable {
    public var phase: PomodoroPhase
    public var remainingSeconds: Int
    public var isPaused: Bool
    public var completedWorkSessions: Int

    /// "mm:ss"
    public var formattedRemaining: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

/// Pure Pomodoro state machine. Time is always passed in, which keeps it deterministic and testable.
public struct PomodoroTimer: Equatable, Sendable {
    public private(set) var settings: PomodoroSettings
    public private(set) var phase: PomodoroPhase = .work
    public private(set) var completedWorkSessions = 0
    private var deadline: Date
    private var pausedRemaining: TimeInterval?

    public init(settings: PomodoroSettings = PomodoroSettings(), startingAt now: Date) {
        self.settings = settings
        self.deadline = now.addingTimeInterval(settings.duration(of: .work))
    }

    public var isPaused: Bool { pausedRemaining != nil }

    public func remaining(at now: Date) -> TimeInterval {
        pausedRemaining ?? max(0, deadline.timeIntervalSince(now))
    }

    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let left = pausedRemaining else { return }
        deadline = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    /// Moves to the next phase when the current one has ended. Returns the new phase, if any.
    public mutating func tick(at now: Date) -> PomodoroPhase? {
        guard !isPaused, now >= deadline else { return nil }
        advance(at: now)
        return phase
    }

    /// Ends the current phase immediately and returns the new one.
    @discardableResult
    public mutating func skip(at now: Date) -> PomodoroPhase {
        advance(at: now)
        return phase
    }

    public func snapshot(at now: Date) -> PomodoroSnapshot {
        PomodoroSnapshot(
            phase: phase,
            remainingSeconds: Int(remaining(at: now).rounded(.up)),
            isPaused: isPaused,
            completedWorkSessions: completedWorkSessions
        )
    }

    private mutating func advance(at now: Date) {
        if phase == .work {
            completedWorkSessions += 1
            phase = completedWorkSessions % settings.sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        let length = settings.duration(of: phase)
        if isPaused {
            pausedRemaining = length
        } else {
            deadline = now.addingTimeInterval(length)
        }
    }
}
