import Foundation

public enum LambaVersion {
    public static let current = "0.1.1"
    /// Bump whenever the app <-> helper protocol changes; the app reinstalls a mismatched helper.
    public static let helperProtocol = 2
}

public enum LambaPaths {
    public static let helperLabel = "dev.hamur.lamba.helper"

    /// Socket of the root helper. `LAMBA_HELPER_SOCKET` overrides it for development only;
    /// the override grants nothing, since the helper itself decides who may talk to it.
    public static var helperSocket: String {
        ProcessInfo.processInfo.environment["LAMBA_HELPER_SOCKET"] ?? "/var/run/\(helperLabel).sock"
    }

    /// Per-user socket of the menu bar app (used by the CLI and the MCP server).
    public static var appSocket: String {
        appSupportDirectory.appendingPathComponent("lamba.sock").path
    }

    public static var appSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lamba", isDirectory: true)
    }
}
