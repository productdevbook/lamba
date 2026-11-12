import Foundation
import LambaCore

/// `lamba ssh-setup <host>`: lets Claude Code on another machine report to Lamba on this Mac.
///
/// 1. Copies `lamba-hook` (Python) to `~/.lamba/` on the host.
/// 2. Adds it to the host's `~/.claude/settings.json` hooks (keeping a backup).
/// 3. Registers the host in `~/.ssh/config` (a `# Lamba:` comment). Lamba then keeps a background
///    `ssh -N -R` tunnel to it, and finds your terminal from your own `ssh <host>` session.
enum SSHSetup {
    static func run(host: String) -> Never {
        guard host.range(of: #"^[A-Za-z0-9._@-]+$"#, options: .regularExpression) != nil else {
            fail("Invalid host name: \(host)")
        }
        guard let script = bundledHookScript() else { fail("lamba-hook not found next to the lamba binary.") }

        print("Connecting to \(host)…")
        let user = ssh(host, #"printf %s "$USER""#).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { fail("Couldn't read the user name on \(host).") }

        _ = ssh(host, "mkdir -p ~/.lamba && cat > ~/.lamba/lamba-hook && chmod +x ~/.lamba/lamba-hook", input: script)
        print("✓ Installed ~/.lamba/lamba-hook on \(host)")

        let result = ssh(host, "python3 -", input: Data(mergeHooksScript.utf8))
        print("✓ Claude Code hooks on \(host): \(result.trimmingCharacters(in: .whitespacesAndNewlines))")

        let remoteSocket = "/tmp/lamba-\(user).sock"
        register(host: host, remoteSocket: remoteSocket)
        print("✓ Registered \(host); Lamba keeps a background tunnel to it (restart Lamba if it's running)")
        print("""

        Done. Claude Code sessions started on \(host) from now on show up in the Lamba Dock
        (sessions already running pick up the hooks after a restart or a look at /hooks).

        Note: unless the host's sshd has `StreamLocalBindUnlink yes`, a socket left from the previous
        connection blocks the forward ("remote port forwarding failed"). As root on \(host):
          echo 'StreamLocalBindUnlink yes' > /etc/ssh/sshd_config.d/50-lamba.conf && systemctl reload ssh
        """)
        exit(0)
    }

    /// Runs a command on the host (batch mode, no prompts) and returns its output.
    private static func ssh(_ host: String, _ command: String, input: Data? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ClearAllForwardings=yes", host, command]
        let output = Pipe()
        let errors = Pipe()
        let stdin = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = stdin
        do { try process.run() } catch { fail("Couldn't run ssh: \(error)") }
        if let input { stdin.fileHandleForWriting.write(input) }
        try? stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fail("ssh \(host) failed: \(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// `lamba` is a symlink into Lamba.app/Contents/Resources, where `lamba-hook` sits too.
    private static func bundledHookScript() -> Data? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            executable.deletingLastPathComponent().appendingPathComponent("lamba-hook"),
            URL(fileURLWithPath: "/usr/local/bin/lamba").resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("lamba-hook"),
        ]
        return candidates.lazy.compactMap { try? Data(contentsOf: $0) }.first
    }

    /// Adds (or replaces) the `# Lamba: <host> <socket>` line Lamba reads its tunnels from.
    private static func register(host: String, remoteSocket: String) {
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let existing = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        let kept = existing.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("# Lamba: \(host) ") }
            .joined(separator: "\n")
        let line = "# Lamba: \(host) \(remoteSocket) (Claude Code on \(host) reports to the Lamba Dock)\n"
        let updated = (kept.hasSuffix("\n") || kept.isEmpty ? kept : kept + "\n") + line
        try? FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(updated.utf8).write(to: config, options: .atomic)
        chmod(config.path, 0o600)
    }

    /// Runs on the host: merges Lamba's hooks into ~/.claude/settings.json.
    private static let mergeHooksScript = #"""
    import json, os, shutil
    path = os.path.expanduser("~/.claude/settings.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    settings = {}
    if os.path.exists(path):
        with open(path) as f:
            settings = json.load(f)
        shutil.copy(path, path + ".lamba-backup")
    hooks = settings.setdefault("hooks", {})
    added = 0
    for hook, action, timeout in [("UserPromptSubmit", "working", None), ("PreToolUse", "tool", None),
                                  ("PermissionRequest", "permission", 600), ("Notification", "waiting", None),
                                  ("Stop", "done", None)]:
        command = "~/.lamba/lamba-hook " + action
        groups = hooks.setdefault(hook, [])
        if any(h.get("command") == command for g in groups for h in g.get("hooks", [])):
            continue
        entry = {"type": "command", "command": command}
        if timeout:
            entry["timeout"] = timeout
        groups.append({"hooks": [entry]})
        added += 1
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"{added} added" if added else "already installed")
    """#
}
