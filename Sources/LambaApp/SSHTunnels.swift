import Foundation
import LambaCore

/// Keeps one background `ssh -N` per host set up with `lamba ssh-setup`, so Claude Code on that
/// host can reach Lamba even when no terminal has an SSH session open with the forward (Warp's
/// own SSH, tmux/Zellij sessions that outlive their connection, connections made before setup).
///
/// Hosts are `# Lamba: <host> <remote socket>` lines in ~/.ssh/config. Only these tunnels forward
/// Lamba's socket; interactive `ssh <host>` sessions don't, so they can't take it over.
final class SSHTunnels {
    private var processes: [String: Process] = [:]
    private var retryDelay: [String: TimeInterval] = [:]
    private var stopped = false
    /// When each host's current tunnel started; a tunnel up for a few seconds counts as connected.
    private var startedAt: [String: Date] = [:]
    var onChange: (() -> Void)?

    /// Tunnel process id → host alias, to recognize requests that arrive through a tunnel.
    private(set) var hostsByPID: [Int32: String] = [:]

    /// Host alias → socket path on that host.
    static var configuredHosts: [String: String] {
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        var hosts: [String: String] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("# Lamba: ") {
            let fields = line.dropFirst("# Lamba: ".count).split(separator: " ")
            if fields.count >= 2, fields[1].hasPrefix("/tmp/lamba-") { hosts[String(fields[0])] = String(fields[1]) }
        }
        return hosts
    }

    func start() {
        stopped = false
        for host in Self.configuredHosts.keys where processes[host] == nil { launch(host) }
    }

    func stop() {
        stopped = true
        processes.values.forEach { $0.terminate() }
        processes = [:]
        hostsByPID = [:]
    }

    /// Stops the tunnel to `host` and removes its `# Lamba:` line from ~/.ssh/config.
    func remove(_ host: String) {
        if let process = processes[host] {
            hostsByPID[process.processIdentifier] = nil
            processes[host] = nil
            startedAt[host] = nil
            process.terminationHandler = nil
            process.terminate()
        }
        retryDelay[host] = nil
        let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        if let text = try? String(contentsOf: config, encoding: .utf8) {
            let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("# Lamba: \(host) ") }
                .joined(separator: "\n")
            try? Data(kept.utf8).write(to: config, options: .atomic)
            chmod(config.path, 0o600)
        }
        onChange?()
    }

    /// Runs `lamba ssh-setup <host>` (bundled CLI) off the main thread, then starts its tunnel.
    func add(_ host: String, completion: @escaping (_ ok: Bool, _ output: String) -> Void) {
        guard let cli = Bundle.main.url(forResource: "lamba", withExtension: nil) else {
            return completion(false, "lamba CLI not found in the app bundle.")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["ssh-setup", host]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            var ok = false
            var output = ""
            do {
                try process.run()
                output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                ok = process.terminationStatus == 0
            } catch {
                output = error.localizedDescription
            }
            DispatchQueue.main.async {
                if ok { self.start() }
                self.onChange?()
                completion(ok, output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func launch(_ host: String) {
        guard !stopped, let remoteSocket = Self.configuredHosts[host] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N", "-T",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=15",
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
            "-R", "\(remoteSocket):\(LambaPaths.appSocket)",
            host,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let started = Date()
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.ended(host, pid: process.processIdentifier, uptime: Date().timeIntervalSince(started)) }
        }
        do {
            try process.run()
            processes[host] = process
            hostsByPID[process.processIdentifier] = host
            startedAt[host] = started
            // ExitOnForwardFailure makes a failed connection exit quickly; report once settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.onChange?() }
        } catch {
            scheduleRetry(host)
        }
    }

    private func ended(_ host: String, pid: Int32, uptime: TimeInterval) {
        processes[host] = nil
        hostsByPID[pid] = nil
        startedAt[host] = nil
        onChange?()
        // A connection that lasted a while resets the backoff; quick failures back off up to a minute.
        if uptime > 60 { retryDelay[host] = nil }
        scheduleRetry(host)
    }

    private func scheduleRetry(_ host: String) {
        guard !stopped else { return }
        let delay = retryDelay[host] ?? 5
        retryDelay[host] = min(delay * 2, 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.processes[host] == nil else { return }
            self.launch(host)
        }
    }

    /// Registered hosts and whether their tunnel is up.
    var status: [(host: String, connected: Bool)] {
        Self.configuredHosts.keys.sorted().map { host in
            (host, startedAt[host].map { Date().timeIntervalSince($0) > 3 } ?? false)
        }
    }

    // MARK: Finding the terminal of a remote session

    private var terminalCache: [String: (host: AgentHost?, date: Date)] = [:]

    /// For a request that came through the tunnel to `host`, the local app and tab where the user
    /// has an interactive `ssh <host>` open (Terminal, iTerm2, Warp, …), if any.
    func interactiveSession(for host: String) -> AgentHost? {
        if let cached = terminalCache[host], Date().timeIntervalSince(cached.date) < 10 { return cached.host }
        let tunnelPIDs = Set(hostsByPID.keys)
        let pids = Self.sshProcesses(to: host).filter { !tunnelPIDs.contains($0) }
        var result: AgentHost?
        for pid in pids {
            let chain = ProcessTree.ancestors(of: pid)
            if let app = chain.first(where: { RunningApps.isRegularApp($0.pid) }) {
                result = AgentHost(pid: app.pid, tty: chain.first { $0.tty != nil }?.tty)
                break
            }
        }
        terminalCache[host] = (result, Date())
        return result
    }

    /// Local `ssh` processes whose destination is `host` (by alias).
    private static func sshProcesses(to host: String) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, fields[1] == "ssh" || fields[1].hasSuffix("/ssh"),
                  fields.dropFirst(3).contains(where: { $0 == host || $0.hasSuffix("@" + host) }) else { return nil }
            return Int32(fields[0])
        }
    }
}
