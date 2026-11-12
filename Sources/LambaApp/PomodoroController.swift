import AppKit
import LambaCore

/// Runs the Pomodoro timer and drives the LED from it:
/// orange while working (slow blink in the last minute), green during breaks, off while paused,
/// and a short flash plus a sound at every phase change.
final class PomodoroController {
    private let light: LightController
    private var timer: PomodoroTimer?
    private var ticker: Timer?
    private var modeBeforeStart: LightMode?

    var onChange: (() -> Void)?
    /// Called when a work phase ends: (start, end, completed). Skipped or stopped phases are partial.
    var onFocusEnded: ((Date, Date, Bool) -> Void)?

    static let finalMinuteWarning: TimeInterval = 60

    init(light: LightController) {
        self.light = light
    }

    var isRunning: Bool { timer != nil }
    var snapshot: PomodoroSnapshot? { timer?.snapshot(at: Date()) }
    var settings: PomodoroSettings? { timer?.settings }

    func start(settings: PomodoroSettings = PomodoroSettings()) {
        if timer == nil { modeBeforeStart = light.mode }
        timer = PomodoroTimer(settings: settings, startingAt: Date())
        startTicker()
        announce(.work)
    }

    func pause() {
        timer?.pause(at: Date())
        updateLight()
        onChange?()
    }

    func resume() {
        timer?.resume(at: Date())
        updateLight()
        onChange?()
    }

    func skip() {
        guard var timer else { return }
        reportFocus(of: timer, completed: false)
        let phase = timer.skip(at: Date())
        self.timer = timer
        announce(phase)
    }

    /// Stops the timer. By default the light goes back to what it was before the timer started.
    func stop(restoreLight: Bool = true) {
        if let timer { reportFocus(of: timer, completed: false) }
        ticker?.invalidate()
        ticker = nil
        timer = nil
        if restoreLight { light.set(modeBeforeStart ?? .solid(.system)) }
        modeBeforeStart = nil
        onChange?()
    }

    private func startTicker() {
        ticker?.invalidate()
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common) // keeps counting while the menu is open
        self.ticker = ticker
    }

    private func tick() {
        guard var timer else { return }
        let before = timer
        let newPhase = timer.tick(at: Date())
        if newPhase != nil { reportFocus(of: before, completed: true) }
        self.timer = timer
        if let newPhase {
            announce(newPhase)
        } else {
            updateLight()
            onChange?()
        }
    }

    /// Reports the time spent in `timer`'s current phase if it is a work phase.
    private func reportFocus(of timer: PomodoroTimer, completed: Bool) {
        guard timer.phase == .work else { return }
        let now = Date()
        let focused = completed ? timer.settings.duration(of: .work) : timer.settings.duration(of: .work) - timer.remaining(at: now)
        onFocusEnded?(now.addingTimeInterval(-focused), now, completed)
    }

    private func announce(_ phase: PomodoroPhase) {
        if Preferences.playSounds {
            NSSound(named: phase.isBreak ? "Glass" : "Hero")?.play()
        }
        if Preferences.haptics {
            Haptics.shared.pulse()
        }
        if Preferences.flashOnPhaseChange {
            light.flash(.flash(phase.isBreak ? .green : .orange, times: 6))
        }
        updateLight()
        onChange?()
    }

    private func updateLight() {
        guard let snapshot else { return }
        let state: LightState
        if snapshot.isPaused {
            state = .off
        } else if snapshot.phase.isBreak {
            state = .green
        } else if TimeInterval(snapshot.remainingSeconds) <= Self.finalMinuteWarning {
            state = .orangeBlinkSlow
        } else {
            state = .orange
        }
        if light.mode != .solid(state) { light.set(.solid(state)) }
    }
}
