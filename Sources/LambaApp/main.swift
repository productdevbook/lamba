import AppKit
import LambaCore

#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--settings-click-test"), index + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
    MainActor.assumeIsolated { PanelSnapshots.clickSidebar(to: CommandLine.arguments[index + 1]) }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--fans"), index + 1 < CommandLine.arguments.count {
    let argument = CommandLine.arguments[index + 1]
    let start = Date()
    do {
        let response = try HelperClient().send(.fans(level: argument == "auto" ? nil : Double(argument)), timeout: 12)
        print(response, String(format: "%.1fs", Date().timeIntervalSince(start)))
    } catch {
        print("error:", error, String(format: "%.1fs", Date().timeIntervalSince(start)))
    }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--convert") {
    let converter = MediaConverter.shared
    converter.set(CommandLine.arguments[(index + 1)...].map { URL(fileURLWithPath: $0) })
    let env = ProcessInfo.processInfo.environment
    converter.maxPixels = 1280
    converter.imageFormat = env["IMAGE"].flatMap(MediaConverter.ImageFormat.init(rawValue:)) ?? .same
    converter.videoPreset = env["VIDEO"].flatMap(MediaConverter.VideoPreset.init(rawValue:)) ?? .p720
    converter.start()
    while converter.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    for job in converter.jobs { print(job.output.path, job.resultSize ?? -1, job.error ?? "") }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { PanelSnapshots.render(to: CommandLine.arguments[index + 1]) }
    exit(0)
}
#endif

// Settings saved under the app's earlier bundle id move over once.
LegacyDefaults.migrate()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
