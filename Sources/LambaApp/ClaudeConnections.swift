import Foundation

/// One-click setup of Lamba's MCP server in Claude Code and Claude Desktop.
enum ClaudeConnections {
    // MARK: Claude Code (MCP)

    private static var claudeCodeConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// Lamba is listed among Claude Code's user-scope MCP servers.
    static var isClaudeCodeConnected: Bool {
        guard let data = try? Data(contentsOf: claudeCodeConfig),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["lamba"] != nil
    }

    /// The `claude` executable, if Claude Code is installed in a usual place.
    static var claudeExecutable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs `claude mcp add --scope user lamba -- <cli> mcp` off the main thread.
    static func connectClaudeCode(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let arguments = ["mcp", "add", "--scope", "user", "lamba", "--", Integrations.cliPath, "mcp"]
            if let claude = claudeExecutable {
                process.executableURL = claude
                process.arguments = arguments
            } else {
                // Fall back to the user's shell, where `claude` may be on PATH.
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-ilc", (["claude"] + arguments).joined(separator: " ")]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let result: Result<Void, Error>
            do {
                try process.run()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                result = process.terminationStatus == 0 || isClaudeCodeConnected
                    ? .success(())
                    : .failure(ConnectionError(message: output.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Claude Desktop

    private static var desktopDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude")
    }

    private static var desktopConfig: URL { desktopDirectory.appendingPathComponent("claude_desktop_config.json") }

    static var isDesktopInstalled: Bool {
        FileManager.default.fileExists(atPath: desktopDirectory.path)
    }

    static var isDesktopConnected: Bool {
        guard let data = try? Data(contentsOf: desktopConfig),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["lamba"] != nil
    }

    /// Adds Lamba to `mcpServers` in Claude Desktop's config, keeping a backup. Takes effect after
    /// Claude Desktop restarts.
    static func connectDesktop() throws {
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: desktopConfig) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            config = parsed
            try data.write(to: desktopConfig.appendingPathExtension("lamba-backup"))
        } else {
            try FileManager.default.createDirectory(at: desktopDirectory, withIntermediateDirectories: true)
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["lamba"] = ["command": Integrations.cliPath, "args": ["mcp"]]
        config["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: desktopConfig, options: .atomic)
    }

    struct ConnectionError: LocalizedError {
        let message: String
        var errorDescription: String? { message.isEmpty ? nil : message }
    }
}
