import AppKit
import LambaCore

/// Installs and removes the root helper (launchd daemon) and the `lamba` CLI, each after one admin prompt.
///
/// For a Developer ID signed release this can be replaced by `SMAppService.daemon(plistName:)`;
/// the helper and its protocol stay the same.
final class HelperInstaller {
    enum Failure: Error, CustomStringConvertible {
        case missingResource(String)
        case cancelled
        case scriptFailed(String)
        case helperDidNotStart

        var description: String {
            switch self {
            case let .missingResource(name): return "Missing resource in app bundle: \(name)"
            case .cancelled: return "Cancelled"
            case let .scriptFailed(message): return message
            case .helperDidNotStart: return "The helper was installed but did not start."
            }
        }
    }

    var isHelperCurrent: Bool {
        guard let response = try? HelperClient().send(.get) else { return false }
        return response.version == LambaVersion.helperProtocol
    }

    /// The `lamba` command must point at this app's copy (it breaks if the app was moved).
    var isCLICurrent: Bool {
        guard let bundled = Bundle.main.path(forResource: "lamba", ofType: nil),
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: Integrations.cliPath) else { return false }
        return URL(fileURLWithPath: target).standardized.path == URL(fileURLWithPath: bundled).standardized.path
    }

    var needsInstall: Bool { !isHelperCurrent || !isCLICurrent }

    func install() throws {
        try runPrivileged(script: "install-helper", arguments: [Bundle.main.bundlePath], prompt: L10n.installPrompt)
        for _ in 0..<30 where !isHelperCurrent {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard isHelperCurrent else { throw Failure.helperDidNotStart }
    }

    func uninstall() throws {
        try runPrivileged(script: "uninstall", arguments: [], prompt: L10n.uninstallPrompt)
    }

    /// Runs a bundled shell script as root after the system admin prompt.
    private func runPrivileged(script name: String, arguments: [String], prompt: String) throws {
        guard let script = Bundle.main.path(forResource: name, ofType: "sh") else {
            throw Failure.missingResource("\(name).sh")
        }
        let quotedArguments = arguments.map { " & \" \" & quoted form of \(literal($0))" }.joined()
        let source = """
        do shell script "/bin/sh " & quoted form of \(literal(script))\(quotedArguments) \
        with administrator privileges with prompt \(literal(prompt))
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -128 = user cancelled the password dialog
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw Failure.cancelled }
            throw Failure.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "Script failed")
        }
    }

    /// AppleScript string literal.
    private func literal(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
