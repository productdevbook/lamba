import AppKit
import LambaCore

/// Brings forward the app an agent runs in and, for Terminal and iTerm2, selects the exact
/// tab by its tty. Other apps (Warp, Ghostty, editors) can't be scripted that way and are
/// just activated. Uses Apple Events, which macOS asks about once per app.
enum TerminalFocus {
    @discardableResult
    static func show(_ host: AgentHost) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: host.pid) else { return false }
        if let tty = host.tty, let script = script(for: app.bundleIdentifier, tty: tty) {
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                if error != nil { DispatchQueue.main.async { app.activate() } }
            }
            return true
        }
        return app.activate()
    }

    private static func script(for bundleID: String?, tty: String) -> String? {
        // The tty comes from the kernel (`/dev/ttysNNN`); reject anything else before quoting it.
        guard tty.range(of: #"^/dev/ttys[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
                                select s
                                select w
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
            end tell
            """
        default:
            return nil
        }
    }
}

