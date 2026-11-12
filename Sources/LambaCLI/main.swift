// `lamba` command line tool. Talks to the running Lamba app; also serves MCP over stdio.

import AppKit
import Foundation
import LambaCore

let usage = """
lamba \(LambaVersion.current) — control the MagSafe LED

USAGE:
  lamba set <state>                 \(LightState.allCases.map(\.rawValue).joined(separator: " | "))
  lamba flash <green|orange> [--times N]
                                    blink N times (default 3), then restore
  lamba alternate                   green and orange taking turns
  lamba pomodoro start [--work MIN] [--break MIN]
  lamba pomodoro pause|resume|stop|skip
  lamba status
  lamba vibrate [--times N]         vibrate the trackpad (default 3)
  lamba report [--days N] [--csv]  focus statistics (default 7 days)
  lamba agent <working|waiting|done> [--session ID] [--hook]
                                    report coding-agent activity; --hook reads the
                                    session from a Claude Code hook's JSON on stdin
  lamba agent tool --hook           PreToolUse hook: show what the agent is doing
  lamba agent permission --hook     PermissionRequest hook: allow or deny in the Dock
  lamba ssh-setup <host>            show Claude Code on <host> (over SSH) in the Dock
  lamba mcp                         run as an MCP server (for Claude and other clients)
  lamba version

"""

enum ExitCode {
    static let failure: Int32 = 1
    static let usage: Int32 = 64
}

func fail(_ message: String, code: Int32 = ExitCode.failure) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usageError(_ message: String) -> Never {
    fail("error: \(message)\n\n\(usage)", code: ExitCode.usage)
}

func optionValue(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func parse(_ args: [String]) -> AppRequest {
    switch args.first {
    case "set":
        guard args.count >= 2, let state = LightState(rawValue: args[1]) else { usageError("unknown state") }
        return .set(state: state)

    case "flash":
        let color = args.count >= 2 && !args[1].hasPrefix("-") ? LightState(rawValue: args[1]) : .green
        guard let color, LightState.flashColors.contains(color) else { usageError("flash color must be green or orange") }
        let times = optionValue("--times", in: args).flatMap(Int.init) ?? 3
        return .flash(color: color, times: times)

    case "alternate":
        return .alternate

    case "pomodoro":
        guard args.count >= 2, let action = PomodoroAction(rawValue: args[1]) else { usageError("unknown pomodoro action") }
        guard action == .start else { return .pomodoro(action: action, settings: nil) }
        var settings = PomodoroSettings()
        if let work = optionValue("--work", in: args).flatMap(Double.init), work > 0 { settings.workMinutes = work }
        if let rest = optionValue("--break", in: args).flatMap(Double.init), rest > 0 { settings.shortBreakMinutes = rest }
        return .pomodoro(action: action, settings: settings)

    case "status":
        return .status

    case "vibrate":
        let times = optionValue("--times", in: args).flatMap(Int.init) ?? 3
        return .vibrate(times: min(max(times, 1), 10))

    case "report":
        let days = optionValue("--days", in: args).flatMap(Int.init) ?? 7
        return .report(days: min(max(days, 1), 365))

    case "agent":
        guard args.count >= 2, let event = AgentEvent(rawValue: args[1]) else { usageError("unknown agent event") }
        let session = optionValue("--session", in: args) ?? (args.contains("--hook") ? Hook.session : nil)
        // The idle reminder ("Claude is waiting for your input") follows a finished turn: not news.
        if event == .waiting, args.contains("--hook"), Hook.isIdleReminder { exit(0) }
        return .agent(event: event, session: session, detail: nil, host: agentHost())

    default:
        usageError("unknown command '\(args.first ?? "")'")
    }
}

/// Claude Code passes hook input as JSON on stdin (`session_id`, `tool_name`, `tool_input`, …).
/// Where the agent runs: the nearest ancestor that is a regular app (Terminal, Warp, VS Code, …)
/// and the first terminal device on the way, so the Dock can bring forward the exact tab.
func agentHost() -> AgentHost? {
    let chain = ProcessTree.ancestors(of: getppid())
    guard let app = chain.first(where: { NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular }) else { return nil }
    let cwd = Hook.input["cwd"] as? String ?? FileManager.default.currentDirectoryPath
    let name = (Hook.input["transcript_path"] as? String).flatMap { SessionTitle.read(transcript: $0) }
    return AgentHost(pid: app.pid, tty: chain.first { $0.tty != nil }?.tty, folder: (cwd as NSString).lastPathComponent, name: name)
}

/// Read lazily (static), so other commands never wait on stdin.
enum Hook {
    static let input: [String: Any] = {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }()

    static var session: String? { input["session_id"] as? String }

    static var isIdleReminder: Bool {
        input["notification_type"] as? String == "idle_prompt"
            || (input["message"] as? String ?? "").localizedCaseInsensitiveContains("waiting for your input")
    }

    static var detail: AgentDetail {
        AgentDetail(hookTool: input["tool_name"] as? String ?? "Tool", input: input["tool_input"] as? [String: Any] ?? [:])
    }
}

/// PreToolUse hook. Never blocks the agent: failures are silent.
func reportTool() -> Never {
    _ = try? AppClient().send(.agent(event: .working, session: Hook.session, detail: Hook.detail, host: agentHost()))
    exit(0)
}

/// PermissionRequest hook: waits for the Dock and prints Claude Code's decision JSON.
/// Printing nothing (Lamba not running, timeout, "ask in terminal") falls back to the normal prompt.
let terminalOnlyTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

func askPermission() -> Never {
    // A question or plan approval needs an answer, not allow/deny: leave it to the terminal.
    if terminalOnlyTools.contains(Hook.detail.tool) { exit(0) }
    let request = AppRequest.permission(session: Hook.session, detail: Hook.detail, host: agentHost())
    guard let response = try? AppClient(timeout: 590).send(request), let decision = response.decision, decision != .ask else { exit(0) }
    var verdict: [String: Any] = ["behavior": decision.rawValue]
    if decision == .deny { verdict["message"] = "Denied from the Lamba Dock." }
    let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": verdict]]
    if let data = try? JSONSerialization.data(withJSONObject: output) {
        FileHandle.standardOutput.write(data)
    }
    exit(0)
}

/// Used when the app is not running: a fixed state can still be set through the helper directly.
func setThroughHelper(_ state: LightState) -> Never {
    do {
        let response = try HelperClient().send(.set(state: state))
        guard response.ok else { fail(response.error ?? "Helper error") }
        print("Light set to \(state.rawValue).")
        exit(0)
    } catch {
        fail("Lamba is not installed or its helper is not running. Open Lamba.app first.")
    }
}

func execute(_ request: AppRequest) -> Never {
    do {
        let response = try AppClient().send(request)
        if let message = response.message { print(message) }
        if case .status = request, let status = response.status { print(status.summary) }
        if let report = response.report {
            print(arguments.contains("--csv") ? report.csv() : report.summary, terminator: arguments.contains("--csv") ? "" : "\n")
        }
        exit(response.ok ? 0 : ExitCode.failure)
    } catch let error as SocketError where error.isNotRunning {
        if case let .set(state) = request { setThroughHelper(state) }
        fail("Lamba is not running. Open Lamba.app first.")
    } catch {
        fail("error: \(error)")
    }
}

signal(SIGPIPE, SIG_IGN)
let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case nil, "help", "-h", "--help":
    print(usage)
case "version", "--version":
    print(LambaVersion.current)
case "mcp":
    MCPServer(service: AppClient()).run()
case "ssh-setup":
    guard arguments.count == 2 else { usageError("usage: lamba ssh-setup <host>") }
    SSHSetup.run(host: arguments[1])
case "agent" where arguments.dropFirst().first == "tool":
    reportTool()
case "agent" where arguments.dropFirst().first == "permission":
    askPermission()
default:
    execute(parse(arguments))
}
