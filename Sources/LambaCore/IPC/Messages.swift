import Foundation

// MARK: - App <-> root helper

/// The complete vocabulary of the root helper. Kept deliberately tiny.
public enum HelperRequest: Codable, Equatable, Sendable {
    case set(state: LightState)
    case get
    /// `pmset -a disablesleep 1/0`: keep the Mac awake, even with the lid closed.
    case sleep(disabled: Bool)
}

public struct HelperResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    public var state: LightState?
    public var version: Int

    public init(ok: Bool, error: String? = nil, state: LightState? = nil, version: Int = LambaVersion.helperProtocol) {
        self.ok = ok
        self.error = error
        self.state = state
        self.version = version
    }
}

// MARK: - Clients (CLI, MCP) <-> app

public enum AppRequest: Codable, Equatable, Sendable {
    case set(state: LightState)
    case alternate
    case flash(color: LightState, times: Int)
    case pomodoro(action: PomodoroAction, settings: PomodoroSettings?)
    case status
    case report(days: Int)
    case vibrate(times: Int)
    /// `host` is where the agent runs (app and terminal tab), so the Dock can bring it forward.
    case agent(event: AgentEvent, session: String?, detail: AgentDetail?, host: AgentHost?)
    /// Asks the user (in the Dock) to allow a tool call; answered with `AppResponse.decision`.
    case permission(session: String?, detail: AgentDetail, host: AgentHost?)
}

public struct AppStatus: Codable, Equatable, Sendable {
    /// e.g. "green", "system", "alternate".
    public var light: String
    public var pomodoro: PomodoroSnapshot?

    public init(light: String, pomodoro: PomodoroSnapshot?) {
        self.light = light
        self.pomodoro = pomodoro
    }

    public var summary: String {
        var lines = ["light: \(light)"]
        if let p = pomodoro {
            let paused = p.isPaused ? " (paused)" : ""
            lines.append("pomodoro: \(p.phase.rawValue) \(p.formattedRemaining) left\(paused), \(p.completedWorkSessions) completed")
        } else {
            lines.append("pomodoro: off")
        }
        return lines.joined(separator: "\n")
    }
}

public struct AppResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String?
    public var status: AppStatus?
    public var report: ActivityReport?
    public var decision: PermissionDecision?

    public init(ok: Bool, message: String? = nil, status: AppStatus? = nil, report: ActivityReport? = nil, decision: PermissionDecision? = nil) {
        self.ok = ok
        self.message = message
        self.status = status
        self.report = report
        self.decision = decision
    }

    public static func success(_ message: String? = nil, status: AppStatus) -> AppResponse {
        AppResponse(ok: true, message: message, status: status)
    }

    public static func failure(_ message: String, status: AppStatus? = nil) -> AppResponse {
        AppResponse(ok: false, message: message, status: status)
    }
}

// MARK: - Encoding

public enum Wire {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
