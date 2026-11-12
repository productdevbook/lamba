import Foundation
import LambaCore

protocol LightWriter {
    func write(_ state: LightState) throws
}

struct HelperLightWriter: LightWriter {
    struct HelperError: Error, CustomStringConvertible {
        let description: String
    }

    private let client = HelperClient()

    func write(_ state: LightState) throws {
        let response = try client.send(.set(state: state))
        guard response.ok else { throw HelperError(description: response.error ?? "Helper error") }
    }
}

enum LightMode: Equatable {
    case solid(LightState)
    case pattern(LightPattern)

    var name: String {
        switch self {
        case let .solid(state): return state.rawValue
        case let .pattern(pattern): return pattern.name
        }
    }
}

/// Owns the LED. A persistent `mode` is shown unless a short `flash` overlay is playing.
final class LightController {
    private let writer: LightWriter
    private(set) var mode: LightMode = .solid(.system)
    private(set) var lastError: String?
    /// What the LED is showing right now, including pattern steps and flashes.
    private(set) var current: LightState = .system
    private var overlay: LightPattern?
    private var player: PatternPlayer?

    var onChange: (() -> Void)?

    init(writer: LightWriter) {
        self.writer = writer
    }

    func set(_ mode: LightMode) {
        self.mode = mode
        if overlay == nil { render() }
        onChange?()
    }

    /// Plays a finite pattern on top of the current mode, then returns to it.
    func flash(_ pattern: LightPattern) {
        // Notification flashes also blink the keyboard backlight, if enabled.
        if pattern.name.hasPrefix("flash-"), pattern.steps.first?.state != .off {
            if Preferences.keyboardFlash { KeyboardLight.shared.flash(times: pattern.repeats ?? 1) }
            if Preferences.capsLockFlash { CapsLockLight.shared.flash(times: pattern.repeats ?? 1) }
        }
        overlay = pattern
        render()
    }

    func restoreSystemControl() {
        player?.stop()
        overlay = nil
        mode = .solid(.system)
        write(.system)
    }

    private func render() {
        player?.stop()
        player = nil

        if let overlay {
            play(overlay) { [weak self] in
                self?.overlay = nil
                self?.render()
            }
            return
        }
        switch mode {
        case let .solid(state): write(state)
        case let .pattern(pattern): play(pattern, completion: nil)
        }
    }

    private func play(_ pattern: LightPattern, completion: (() -> Void)?) {
        let player = PatternPlayer(pattern: pattern, write: { [weak self] in self?.write($0) }, completion: completion)
        self.player = player
        player.start()
    }

    private func write(_ state: LightState) {
        let failure: String?
        do {
            try writer.write(state)
            failure = nil
        } catch let error as SocketError where error.isNotRunning {
            failure = L10n.helperNotRunning
        } catch {
            failure = "\(error)"
        }
        let changed = failure != lastError || state != current
        lastError = failure
        current = state
        if changed { onChange?() }
    }
}

/// Steps through a pattern with main run loop timers.
final class PatternPlayer {
    private let pattern: LightPattern
    private let write: (LightState) -> Void
    private let completion: (() -> Void)?
    private var timer: Timer?
    private var index = 0
    private var completedCycles = 0

    init(pattern: LightPattern, write: @escaping (LightState) -> Void, completion: (() -> Void)?) {
        self.pattern = pattern
        self.write = write
        self.completion = completion
    }

    func start() {
        step()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        if index == pattern.steps.count {
            index = 0
            completedCycles += 1
            if let repeats = pattern.repeats, completedCycles >= repeats {
                completion?()
                return
            }
        }
        let step = pattern.steps[index]
        index += 1
        write(step.state)

        let timer = Timer(timeInterval: step.duration, repeats: false) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
