import Foundation
import LambaCore

struct AgentSessionInfo: Identifiable, Equatable {
    let state: AgentSessionState
    let host: AgentHost?
    /// The session's name (Claude Code's title for it), when known.
    let name: String?
    var id: String { state.id }
}

/// A tool call waiting for the user's answer in the Dock.
struct PermissionPrompt: Identifiable, Equatable {
    let id = UUID()
    let session: String?
    let detail: AgentDetail
    let host: AgentHost?
}

/// Holds coding-agent activity reported through `lamba agent …`, expires it over time,
/// and keeps permission requests until the user answers them in the Dock.
final class AgentMonitor {
    /// Just under the hook's own timeout, so the agent always gets an answer.
    static let permissionTimeout: TimeInterval = 580

    private var activity = AgentActivity()
    private var timer: Timer?
    private var pending: [(prompt: PermissionPrompt, reply: (PermissionDecision) -> Void)] = []
    var onChange: (() -> Void)?
    /// App each session runs in, and the session that reported last.
    private var hosts: [String: AgentHost] = [:]
    private var lastSession: String?

    /// The app of the most recently active session.
    var host: AgentHost? { hosts[lastSession ?? "default"] }

    var summary: AgentSummary? { activity.summary(at: Date()) }

    /// Live sessions with where they run.
    var sessions: [AgentSessionInfo] {
        activity.sessions(at: Date()).map { state in
            let host = hosts[state.id]
            return AgentSessionInfo(state: state, host: host, name: host?.name)
        }
    }
    var prompt: PermissionPrompt? { pending.first?.prompt }
    /// A session finished its turn (for the Dock's announcement).
    var onFinish: ((AgentSessionInfo) -> Void)?

    /// Returns false when the event was ignored.
    @discardableResult
    func record(_ event: AgentEvent, session: String?, detail: AgentDetail?, host: AgentHost? = nil) -> Bool {
        // Claude Code's "waiting for your input" reminder arrives a while after a turn ends; the
        // session is finished, not asking for anything (permission prompts come mid-turn).
        if event == .waiting, sessions.first(where: { $0.id == (session ?? "default") })?.state.event == .done {
            return false
        }
        activity.record(event, session: session, detail: detail, at: Date())
        if let host { remember(host, for: session) }
        lastSession = session ?? "default"
        // A new prompt or the end of the turn means the question was settled elsewhere
        // (answered in the terminal, or the turn was interrupted).
        if event == .done || (event == .working && detail == nil) {
            for item in pending where item.prompt.session == session { resolve(item.prompt.id, .ask) }
        }
        onChange?()
        if event == .done, let finished = sessions.first(where: { $0.id == (session ?? "default") }) {
            onFinish?(finished)
        }
        scheduleExpiry()
        return true
    }

    func requestPermission(session: String?, detail: AgentDetail, host: AgentHost?, reply: @escaping (PermissionDecision) -> Void) {
        if let host { remember(host, for: session) }
        if ["AskUserQuestion", "ExitPlanMode"].contains(detail.tool) { return reply(.ask) }
        let prompt = PermissionPrompt(session: session, detail: detail, host: host)
        pending.append((prompt, reply))
        onChange?()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.permissionTimeout) { [weak self] in
            self?.resolve(prompt.id, .ask)
        }
    }

    func resolve(_ id: UUID, _ decision: PermissionDecision) {
        guard let index = pending.firstIndex(where: { $0.prompt.id == id }) else { return }
        let item = pending.remove(at: index)
        item.reply(decision)
        if decision == .allow { activity.record(.working, session: item.prompt.session, detail: item.prompt.detail, at: Date()) }
        onChange?()
    }

    /// Keeps a known name when a later report has none (e.g. before the title is generated).
    private func remember(_ host: AgentHost, for session: String?) {
        let id = session ?? "default"
        var host = host
        if host.name == nil { host.name = hosts[id]?.name }
        hosts[id] = host
    }

    /// Checks periodically while anything is shown, so "done" and stale sessions disappear.
    private func scheduleExpiry() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if self.activity.prune(at: Date()) { self.onChange?() }
            if self.summary == nil, self.activity.sessions(at: Date()).isEmpty {
                timer.invalidate()
                self.timer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
