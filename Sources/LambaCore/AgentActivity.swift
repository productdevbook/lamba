import Foundation

/// What a coding agent (e.g. Claude Code, through its hooks) reports to Lamba.
public enum AgentEvent: String, Codable, CaseIterable, Sendable {
    /// A prompt was submitted; the agent is working.
    case working
    /// The agent needs the user (permission prompt, question).
    case waiting
    /// The agent finished its turn.
    case done
}

/// What the agent is doing: a tool and its target, e.g. `Edit` + `Dock.swift`.
public struct AgentDetail: Codable, Hashable, Sendable {
    public var tool: String
    public var target: String?

    public init(tool: String, target: String? = nil) {
        self.tool = tool
        self.target = target
    }

    public static let maxTargetLength = 48

    /// Builds a detail from a Claude Code hook's `tool_name` and `tool_input`.
    public init(hookTool tool: String, input: [String: Any]) {
        func string(_ key: String) -> String? {
            (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        var target: String?
        if let path = string("file_path") ?? string("notebook_path") ?? string("path") {
            target = (path as NSString).lastPathComponent
        } else if let url = string("url") {
            target = URL(string: url)?.host ?? url
        } else {
            target = string("description") ?? string("command") ?? string("pattern") ?? string("query") ?? string("prompt")
        }
        if let value = target?.replacingOccurrences(of: "\n", with: " "), value.count > Self.maxTargetLength {
            target = String(value.prefix(Self.maxTargetLength - 1)) + "…"
        } else {
            target = target?.replacingOccurrences(of: "\n", with: " ")
        }
        self.init(tool: tool, target: target)
    }
}

/// The app an agent runs in, and its terminal device (e.g. `/dev/ttys003`) to find the tab.
public struct AgentHost: Codable, Hashable, Sendable {
    public var pid: Int32
    public var tty: String?
    /// Name of the project folder the agent works in, to tell sessions apart.
    public var folder: String?
    /// The machine it runs on: `nil` for this Mac, else the SSH host alias (or host name).
    public var machine: String?
    /// The session's title, as Claude Code names it (`/rename`, or its generated title).
    public var name: String?

    public init(pid: Int32, tty: String?, folder: String? = nil, name: String? = nil, machine: String? = nil) {
        self.pid = pid
        self.tty = tty
        self.folder = folder
        self.name = name
        self.machine = machine
    }
}

/// Finds a Claude Code session's title in its transcript (JSONL): the last `custom-title`
/// (set with /rename) or `ai-title` entry. Only the end of the file is read.
public enum SessionTitle {
    public static func read(transcript path: String, tailBytes: Int = 512 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ text: String) -> String? {
        var aiTitle: String?
        for line in text.split(separator: "\n").reversed() where line.contains("-title\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if json["type"] as? String == "custom-title", let title = json["customTitle"] as? String, !title.isEmpty {
                return title
            }
            if aiTitle == nil, json["type"] as? String == "ai-title", let title = json["aiTitle"] as? String, !title.isEmpty {
                aiTitle = title
            }
        }
        return aiTitle
    }
}

/// One agent session as the Dock shows it.
public struct AgentSessionState: Equatable, Sendable {
    public var id: String
    public var event: AgentEvent
    public var detail: AgentDetail?
    /// When the session first reported, and when it last did.
    public var started: Date
    public var updated: Date
}

public enum PermissionDecision: String, Codable, Sendable {
    case allow
    case deny
    /// Let the agent ask in its own UI (terminal) instead.
    case ask
}

/// What the Dock shows for all agent sessions together.
public enum AgentSummary: Equatable, Sendable {
    case working(sessions: Int, detail: AgentDetail?)
    case waiting(sessions: Int)
    case done
}

/// Tracks agent sessions and reduces them to one `AgentSummary`.
///
/// Waiting beats working beats a recent "done". Sessions that stop reporting expire, so a
/// crashed agent can't leave the Dock saying "working" forever.
public struct AgentActivity: Sendable {
    /// How long a finished turn counts as "just done" for the Dock icon.
    public static let doneVisibleFor: TimeInterval = 8
    /// Sessions (working or finished) are listed until they've been quiet this long.
    public static let staleAfter: TimeInterval = 30 * 60

    private var sessions: [String: (event: AgentEvent, date: Date, detail: AgentDetail?)] = [:]
    /// First time each session reported, so their order stays stable.
    private var firstSeen: [String: Date] = [:]

    public init() {}

    public mutating func record(_ event: AgentEvent, session: String?, detail: AgentDetail? = nil, at date: Date) {
        let id = session ?? "default"
        sessions[id] = (event, date, detail)
        if firstSeen[id] == nil { firstSeen[id] = date }
    }

    /// Live sessions in the order they first appeared.
    public func sessions(at date: Date) -> [AgentSessionState] {
        var copy = self
        copy.prune(at: date)
        return copy.sessions
            .sorted { (copy.firstSeen[$0.key] ?? .distantPast) < (copy.firstSeen[$1.key] ?? .distantPast) }
            .map {
                AgentSessionState(
                    id: $0.key, event: $0.value.event, detail: $0.value.detail,
                    started: copy.firstSeen[$0.key] ?? $0.value.date, updated: $0.value.date
                )
            }
    }

    /// Drops expired sessions; returns true if anything changed.
    @discardableResult
    public mutating func prune(at date: Date) -> Bool {
        let before = sessions.count
        sessions = sessions.filter { _, value in
            let age = date.timeIntervalSince(value.date)
            return age < Self.staleAfter
        }
        firstSeen = firstSeen.filter { sessions[$0.key] != nil }
        return sessions.count != before
    }

    public func summary(at date: Date) -> AgentSummary? {
        var copy = self
        copy.prune(at: date)
        let events = copy.sessions.values.map(\.event)
        let waiting = events.filter { $0 == .waiting }.count
        if waiting > 0 { return .waiting(sessions: waiting) }
        let working = copy.sessions.values.filter { $0.event == .working }
        if let latest = working.max(by: { $0.date < $1.date }) {
            return .working(sessions: working.count, detail: latest.detail)
        }
        let justDone = copy.sessions.values.contains { $0.event == .done && date.timeIntervalSince($0.date) < Self.doneVisibleFor }
        return justDone ? .done : nil
    }
}
