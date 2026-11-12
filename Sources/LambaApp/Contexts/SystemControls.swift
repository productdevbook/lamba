import AppKit
import IOKit.pwr_mgt

/// Runs a one-line AppleScript on the calling thread. Returns the result, or nil on failure.
/// Apple Events to System Events ask the user for permission the first time.
private func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    return error == nil ? result : nil
}

/// macOS light/dark appearance.
enum SystemAppearance {
    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Switches the system appearance (Apple Events to System Events; asks for permission once).
    static func setDark(_ dark: Bool) {
        guard dark != isDark else { return }
        _ = runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
    }
}

/// Runs the user's Shortcuts (e.g. one that turns a Focus mode on).
enum ShortcutsRunner {
    private static let tool = "/usr/bin/shortcuts"
    private static let lock = NSLock()
    private static var cache: [String]?

    /// Names of the user's shortcuts (`shortcuts list`). Cached after the first successful call;
    /// the first call blocks for at most a few seconds, so call it off the main thread when possible.
    static func list() -> [String] {
        lock.lock()
        let cached = cache
        lock.unlock()
        if let cached { return cached }

        guard let output = capture(arguments: ["list"], timeout: 5) else { return [] }
        let names = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        lock.lock()
        cache = names
        lock.unlock()
        return names
    }

    /// Forgets the cached list (e.g. when the settings open, so new shortcuts show up).
    static func invalidateCache() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    /// Starts the shortcut and returns immediately.
    static func run(_ name: String) {
        guard !name.isEmpty, FileManager.default.isExecutableFile(atPath: tool) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
    }

    private static func capture(arguments: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: tool) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        var data = Data()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Microphone input volume. "Muted" means input volume 0; the previous level is restored on unmute.
enum Microphone {
    private static let savedKey = "microphoneVolumeBeforeMute"

    private static var inputVolume: Int? {
        runAppleScript("input volume of (get volume settings)").map { Int($0.int32Value) }
    }

    static var isMuted: Bool { inputVolume == 0 }

    static func setMuted(_ muted: Bool) {
        if muted {
            if let volume = inputVolume, volume > 0 {
                UserDefaults.standard.set(volume, forKey: savedKey)
            }
            _ = runAppleScript("set volume input volume 0")
        } else {
            let saved = UserDefaults.standard.integer(forKey: savedKey)
            _ = runAppleScript("set volume input volume \(saved > 0 ? min(saved, 100) : 75)")
        }
    }
}

/// Keeps the Mac (and display) awake while on.
enum KeepAwake {
    private static var assertion: IOPMAssertionID = 0
    private static var active = false

    static var isOn: Bool { active }

    static func set(_ on: Bool) {
        guard on != active else { return }
        if on {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), "Lamba keep awake" as CFString, &id)
            if result == kIOReturnSuccess {
                assertion = id
                active = true
            }
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            active = false
        }
    }
}
