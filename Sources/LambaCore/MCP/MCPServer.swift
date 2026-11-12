import Foundation

/// Minimal Model Context Protocol server (JSON-RPC 2.0 over stdio, tools only).
/// Lets Claude Desktop, Claude Code and other MCP clients drive the light.
public final class MCPServer {
    public static let fallbackProtocolVersion = "2025-06-18"

    private let service: LambaService

    public init(service: LambaService) {
        self.service = service
    }

    /// Serves until stdin closes.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let reply = handle(line) else { continue }
            print(reply)
            fflush(stdout)
        }
    }

    /// Handles one JSON-RPC message; returns the reply, or `nil` for notifications.
    public func handle(_ line: String) -> String? {
        guard
            let data = line.data(using: .utf8),
            let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }

        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return reply(id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? Self.fallbackProtocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "lamba", "version": LambaVersion.current],
                "instructions": "Controls the MagSafe charging LED of this Mac. Use flash_light to get the user's attention, e.g. when a long task finishes.",
            ])
        case "ping":
            return reply(id, result: [String: Any]())
        case "tools/list":
            return reply(id, result: ["tools": MCPTools.definitions])
        case "tools/call":
            return reply(id, result: callTool(params))
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private func callTool(_ params: [String: Any]) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let request = try MCPTools.request(for: name, arguments: arguments)
            let response = try service.send(request)
            let text = [response.message, response.report?.summary ?? response.status?.summary]
                .compactMap { $0 }.joined(separator: "\n")
            return toolResult(text.isEmpty ? "OK" : text, isError: !response.ok)
        } catch let error as SocketError where error.isNotRunning {
            return toolResult("The Lamba app is not running. Ask the user to open Lamba.", isError: true)
        } catch {
            return toolResult("\(error)", isError: true)
        }
    }

    private func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func reply(_ id: Any, result: [String: Any]) -> String? {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

public enum MCPToolError: Error, CustomStringConvertible, Equatable {
    case unknownTool(String)
    case invalidArgument(String)

    public var description: String {
        switch self {
        case let .unknownTool(name): return "Unknown tool: \(name)"
        case let .invalidArgument(detail): return "Invalid argument: \(detail)"
        }
    }
}

enum MCPTools {
    static let definitions: [[String: Any]] = [
        [
            "name": "set_light",
            "description": "Set the MagSafe LED to a fixed state. 'system' gives control back to macOS.",
            "inputSchema": [
                "type": "object",
                "properties": ["state": ["type": "string", "enum": LightState.allCases.map(\.rawValue)]],
                "required": ["state"],
            ],
        ],
        [
            "name": "flash_light",
            "description": "Blink the MagSafe LED a few times to notify the user, then return to the previous state.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "color": ["type": "string", "enum": LightState.flashColors.map(\.rawValue)],
                    "times": ["type": "integer", "minimum": 1, "maximum": LightPattern.maxFlashCount, "default": 3],
                ],
                "required": ["color"],
            ],
        ],
        [
            "name": "pomodoro",
            "description": "Control the Pomodoro timer. The LED is orange while working and green during breaks.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "enum": PomodoroAction.allCases.map(\.rawValue)],
                    "work_minutes": ["type": "number", "minimum": 1, "description": "Only for start. Default 25."],
                    "break_minutes": ["type": "number", "minimum": 1, "description": "Only for start. Default 5."],
                ],
                "required": ["action"],
            ],
        ],
        [
            "name": "vibrate",
            "description": "Vibrate the Mac's trackpad a few times to get the user's attention (felt through the case even without touching it).",
            "inputSchema": [
                "type": "object",
                "properties": ["times": ["type": "integer", "minimum": 1, "maximum": 10, "default": 3]],
            ],
        ],
        [
            "name": "get_report",
            "description": "Get the user's local focus statistics: focus time per day, completed Pomodoro sessions, streak, light and charger usage.",
            "inputSchema": [
                "type": "object",
                "properties": ["days": ["type": "integer", "minimum": 1, "maximum": 365, "default": 7]],
            ],
        ],
        [
            "name": "get_status",
            "description": "Get the current LED mode and Pomodoro state.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ]

    static func request(for tool: String, arguments: [String: Any]) throws -> AppRequest {
        switch tool {
        case "set_light":
            guard let raw = arguments["state"] as? String, let state = LightState(rawValue: raw) else {
                throw MCPToolError.invalidArgument("state")
            }
            return .set(state: state)

        case "flash_light":
            guard
                let raw = arguments["color"] as? String,
                let color = LightState(rawValue: raw),
                LightState.flashColors.contains(color)
            else { throw MCPToolError.invalidArgument("color") }
            let times = (arguments["times"] as? NSNumber)?.intValue ?? 3
            return .flash(color: color, times: times)

        case "pomodoro":
            guard let raw = arguments["action"] as? String, let action = PomodoroAction(rawValue: raw) else {
                throw MCPToolError.invalidArgument("action")
            }
            var settings: PomodoroSettings?
            if action == .start {
                var s = PomodoroSettings()
                if let work = (arguments["work_minutes"] as? NSNumber)?.doubleValue, work > 0 { s.workMinutes = work }
                if let rest = (arguments["break_minutes"] as? NSNumber)?.doubleValue, rest > 0 { s.shortBreakMinutes = rest }
                settings = s
            }
            return .pomodoro(action: action, settings: settings)

        case "vibrate":
            let times = (arguments["times"] as? NSNumber)?.intValue ?? 3
            return .vibrate(times: min(max(times, 1), 10))

        case "get_report":
            let days = (arguments["days"] as? NSNumber)?.intValue ?? 7
            return .report(days: min(max(days, 1), 365))

        case "get_status":
            return .status

        default:
            throw MCPToolError.unknownTool(tool)
        }
    }
}
