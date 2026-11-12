// Lamba root helper.
//
// Runs as a launchd daemon and is the only Lamba component with root rights. It does exactly two
// things: read or write the MagSafe LED key (only whitelisted `LightState` values) and turn system
// sleep on or off (`pmset disablesleep`), only from root or the user currently logged in at the console.

import CSMC
import Foundation
import LambaCore
import SystemConfiguration

func consoleUserID() -> uid_t? {
    var uid = uid_t(0)
    guard SCDynamicStoreCopyConsoleUser(nil, &uid, nil) != nil else { return nil }
    return uid
}

func describe(_ status: lamba_smc_status) -> String {
    switch status {
    case LAMBA_SMC_OPEN_FAILED: return "Could not open the SMC."
    case LAMBA_SMC_KEY_MISSING: return "This Mac has no MagSafe LED."
    case LAMBA_SMC_IO_FAILED: return "The SMC rejected the request (is the helper running as root?)."
    default: return "Unknown SMC error."
    }
}

func respond(to request: HelperRequest) -> HelperResponse {
    switch request {
    case let .set(state):
        let status = lamba_smc_write_led(state.smcValue)
        return status == LAMBA_SMC_OK ? HelperResponse(ok: true, state: state) : HelperResponse(ok: false, error: describe(status))
    case let .sleep(disabled):
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return HelperResponse(ok: false, error: "pmset: \(error)")
        }
        return process.terminationStatus == 0 ? HelperResponse(ok: true) : HelperResponse(ok: false, error: "pmset failed.")
    case .get:
        var value: UInt8 = 0
        let status = lamba_smc_read_led(&value)
        return status == LAMBA_SMC_OK
            ? HelperResponse(ok: true, state: LightState(smcValue: value))
            : HelperResponse(ok: false, error: describe(status))
    }
}

func handle(_ data: Data) -> Data {
    let response: HelperResponse
    if let request = try? Wire.decode(HelperRequest.self, from: data) {
        response = respond(to: request)
    } else {
        response = HelperResponse(ok: false, error: "Malformed request.")
    }
    return (try? Wire.encode(response)) ?? Data()
}

// `--socket <path>` exists for development (running the helper unprivileged against a temp path).
var socketPath = LambaPaths.helperSocket
if let index = CommandLine.arguments.firstIndex(of: "--socket"), index + 1 < CommandLine.arguments.count {
    socketPath = CommandLine.arguments[index + 1]
}

signal(SIGPIPE, SIG_IGN)

let server: UnixSocketServer
do {
    server = try UnixSocketServer(
        path: socketPath,
        permissions: 0o666, // reachable by everyone; access is decided per connection below
        queue: DispatchQueue(label: "app.lamba.helper.ipc"),
        authorize: { uid in uid == 0 || uid == getuid() || uid == consoleUserID() },
        handler: handle
    )
} catch {
    FileHandle.standardError.write(Data("lamba-helper: \(error)\n".utf8))
    exit(1)
}

withExtendedLifetime(server) { dispatchMain() }
