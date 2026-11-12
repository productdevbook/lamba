import AppKit

/// Ready-to-paste snippets for connecting Claude and scripts, shown in Settings › Integrations.
enum Integrations {
    static let cliPath = "/usr/local/bin/lamba"

    static var claudeCodeCommand: String {
        "claude mcp add lamba -- \(cliPath) mcp"
    }

    static var claudeDesktopConfig: String {
        """
        {
          "mcpServers": {
            "lamba": { "command": "\(cliPath)", "args": ["mcp"] }
          }
        }
        """
    }

    static var claudeCodeHooks: String {
        """
        {
          "hooks": {
            "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "\(cliPath) agent working --hook" }] }],
            "PreToolUse": [{ "hooks": [{ "type": "command", "command": "\(cliPath) agent tool --hook" }] }],
            "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "\(cliPath) agent permission --hook", "timeout": 600 }] }],
            "Notification": [{ "hooks": [{ "type": "command", "command": "\(cliPath) agent waiting --hook" }] }],
            "Stop": [{ "hooks": [{ "type": "command", "command": "\(cliPath) agent done --hook" }] }]
          }
        }
        """
    }

    static var cliExamples: String {
        """
        lamba set green
        lamba flash orange --times 5
        lamba pomodoro start --work 50 --break 10
        make build && lamba flash green || lamba flash orange
        """
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
