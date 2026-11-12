import AppKit
import CSMC

enum HardwareSupport {
    /// Whether this Mac exposes the MagSafe LED key. Reading needs no root, so this works before setup.
    static let hasMagSafeLED: Bool = {
        var value: UInt8 = 0
        return lamba_smc_read_led(&value) != LAMBA_SMC_KEY_MISSING
    }()
}

enum RunningApps {
    /// True for apps with a Dock presence (Terminal, Warp, VS Code, …), not agents or daemons.
    static func isRegularApp(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
    }
}
