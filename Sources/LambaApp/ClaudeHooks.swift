import Foundation

/// Adds Lamba's hooks to Claude Code's user settings (`~/.claude/settings.json`), so the Dock
/// shows when Claude is working, needs you, or is done. Existing settings and hooks are kept,
/// and a backup of the file is written first.
enum ClaudeHooks {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Claude Code hook event → `lamba agent` argument, and a timeout for hooks that wait for the user.
    static let events: [(hook: String, event: String, timeout: Int?)] = [
        ("UserPromptSubmit", "working", nil),
        ("PreToolUse", "tool", nil),
        ("PermissionRequest", "permission", 600),
        ("Notification", "waiting", nil),
        ("Stop", "done", nil),
    ]

    static func command(for event: String) -> String {
        "\(Integrations.cliPath) agent \(event) --hook"
    }

    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL), let text = String(data: data, encoding: .utf8) else { return false }
        return events.allSatisfy { text.contains(command(for: $0.event)) }
    }

    static func install() throws {
        let fileManager = FileManager.default
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            settings = parsed
            try data.write(to: settingsURL.appendingPathExtension("lamba-backup"))
        } else {
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (hook, event, timeout) in events {
            var groups = hooks[hook] as? [[String: Any]] ?? []
            let command = command(for: event)
            let alreadyThere = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
            }
            if !alreadyThere {
                var entry: [String: Any] = ["type": "command", "command": command]
                if let timeout { entry["timeout"] = timeout }
                groups.append(["hooks": [entry]])
            }
            hooks[hook] = groups
        }
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
