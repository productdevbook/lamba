import AppKit
import Foundation
import LambaCore

/// Executes requests coming from the CLI / MCP server. Must be called on the main thread.
final class RequestRouter {
    private let light: LightController
    private let pomodoro: PomodoroController
    private let activity: ActivityTracker
    private let agents: AgentMonitor
    /// Background SSH tunnels; requests through them are matched to the user's terminal.
    weak var tunnels: SSHTunnels?

    init(light: LightController, pomodoro: PomodoroController, activity: ActivityTracker, agents: AgentMonitor) {
        self.light = light
        self.pomodoro = pomodoro
        self.activity = activity
        self.agents = agents
    }

    var status: AppStatus {
        AppStatus(light: light.mode.name, pomodoro: pomodoro.snapshot)
    }

    func handle(_ data: Data) -> Data {
        let response: AppResponse
        if let request = try? Wire.decode(AppRequest.self, from: data) {
            response = handle(request)
        } else {
            response = .failure("Malformed request.")
        }
        return (try? Wire.encode(response)) ?? Data()
    }

    /// Like `handle(_:)`, but permission requests answer later, when the user decides in the Dock.
    func handle(_ data: Data, peer: Int32?, reply: @escaping (Data) -> Void) {
        guard var request = try? Wire.decode(AppRequest.self, from: data) else { return reply(handle(data)) }
        request = fillingHost(of: request, peer: peer)
        guard case let .permission(session, detail, host) = request else {
            let response = handle(request)
            return reply((try? Wire.encode(response)) ?? Data())
        }
        signal(.orange, times: 3)
        agents.requestPermission(session: session, detail: detail, host: host) { [weak self] decision in
            let response = AppResponse(ok: true, status: self?.status, decision: decision)
            reply((try? Wire.encode(response)) ?? Data())
        }
    }

    func handle(_ request: AppRequest) -> AppResponse {
        let message: String?
        switch request {
        case let .set(state):
            setManually(.solid(state))
            message = "Light set to \(state.rawValue)."

        case .alternate:
            setManually(.pattern(.alternate))
            message = "Light alternating green/orange."

        case let .flash(color, times):
            guard LightState.flashColors.contains(color) else {
                return .failure("Flash color must be green or orange.", status: status)
            }
            signal(color, times: times)
            message = "Flashing \(color.rawValue)."

        case let .pomodoro(action, settings):
            message = handlePomodoro(action, settings: settings)

        case .status:
            message = nil

        case let .vibrate(times):
            Haptics.shared.pulse(times: times)
            message = "Vibrating."

        case let .permission(session, detail, host):
            // Answered asynchronously through `handle(_:reply:)`; reaching here means no reply path.
            agents.record(.waiting, session: session, detail: detail, host: host)
            message = "Permission requests need a waiting client."

        case let .agent(event, session, detail, host):
            let recorded = agents.record(event, session: session, detail: detail, host: host)
            switch event {
            case .working: break
            case .waiting where recorded: signal(.orange, times: 5)
            case .waiting: break
            case .done: signal(.green, times: 3)
            }
            message = "Agent \(event.rawValue)."

        case let .report(days):
            return AppResponse(ok: true, status: status, report: activity.report(days: days))
        }

        if let error = light.lastError {
            return .failure(error, status: status)
        }
        return .success(message, status: status)
    }

    /// Requests from remote machines (through an SSH-forwarded socket) can't know where they run
    /// on this Mac; the connecting process — the local `ssh` client — tells: its app and tab.
    /// Through Lamba's own background tunnel, the user's interactive `ssh <host>` is used instead.
    func fillingHost(of request: AppRequest, peer: Int32?) -> AppRequest {
        func resolve(_ host: AgentHost?) -> AgentHost? {
            guard host == nil || host?.pid == 0, let peer else { return host }
            var local: AgentHost?
            var machine = host?.machine
            if let alias = tunnels?.hostsByPID[peer] {
                machine = alias
                local = tunnels?.interactiveSession(for: alias)
            } else {
                let chain = ProcessTree.ancestors(of: peer)
                if let app = chain.first(where: { RunningApps.isRegularApp($0.pid) }) {
                    local = AgentHost(pid: app.pid, tty: chain.first { $0.tty != nil }?.tty)
                }
            }
            return AgentHost(pid: local?.pid ?? 0, tty: local?.tty, folder: host?.folder, name: host?.name, machine: machine)
        }
        switch request {
        case let .agent(event, session, detail, host):
            return .agent(event: event, session: session, detail: detail, host: resolve(host))
        case let .permission(session, detail, host):
            return .permission(session: session, detail: detail, host: resolve(host))
        default:
            return request
        }
    }

    /// Flashes the LED and vibrates, as configured.
    private func signal(_ color: LightState, times: Int) {
        light.flash(.flash(color, times: times))
        activity.flashed(color)
        if Preferences.haptics { Haptics.shared.pulse() }
    }

    /// A manual light choice ends a running Pomodoro, so the two never fight over the LED.
    func setManually(_ mode: LightMode) {
        if pomodoro.isRunning { pomodoro.stop(restoreLight: false) }
        light.set(mode)
    }

    private func handlePomodoro(_ action: PomodoroAction, settings: PomodoroSettings?) -> String {
        switch action {
        case .start:
            pomodoro.start(settings: settings ?? PomodoroSettings())
            return "Pomodoro started."
        case .pause:
            pomodoro.pause()
            return "Pomodoro paused."
        case .resume:
            pomodoro.resume()
            return "Pomodoro resumed."
        case .skip:
            pomodoro.skip()
            return "Skipped to the next phase."
        case .stop:
            pomodoro.stop()
            return "Pomodoro stopped."
        }
    }
}
