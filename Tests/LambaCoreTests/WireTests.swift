import XCTest
@testable import LambaCore

final class WireTests: XCTestCase {
    func testSMCValuesRoundTrip() {
        for state in LightState.allCases {
            XCTAssertEqual(LightState(smcValue: state.smcValue), state)
        }
        XCTAssertNil(LightState(smcValue: 2))
        XCTAssertNil(LightState(smcValue: 255))
    }

    func testAppRequestsRoundTrip() throws {
        let requests: [AppRequest] = [
            .set(state: .green),
            .alternate,
            .flash(color: .orange, times: 4),
            .pomodoro(action: .start, settings: PomodoroSettings(workMinutes: 50)),
            .pomodoro(action: .stop, settings: nil),
            .status,
            .report(days: 7),
            .vibrate(times: 3),
            .agent(event: .waiting, session: "abc", detail: nil, host: AgentHost(pid: 42, tty: "/dev/ttys003")),
            .agent(event: .working, session: nil, detail: AgentDetail(tool: "Edit", target: "a.swift"), host: nil),
            .permission(session: "abc", detail: AgentDetail(tool: "Bash", target: "rm -rf build"), host: AgentHost(pid: 7, tty: nil)),
        ]
        for request in requests {
            XCTAssertEqual(try Wire.decode(AppRequest.self, from: Wire.encode(request)), request)
        }
    }

    /// The shape `Support/lamba-hook` (Python, on remote machines) sends.
    func testRemoteHookRequestDecodes() throws {
        let json = #"{"agent": {"event": "working", "session": "s1", "host": {"pid": 0, "folder": "server:web"}, "detail": {"tool": "Edit", "target": "a.py"}}}"#
        XCTAssertEqual(
            try Wire.decode(AppRequest.self, from: Data(json.utf8)),
            .agent(event: .working, session: "s1", detail: AgentDetail(tool: "Edit", target: "a.py"), host: AgentHost(pid: 0, tty: nil, folder: "server:web"))
        )
        let permission = #"{"permission": {"session": null, "detail": {"tool": "Bash"}, "host": {"pid": 0, "folder": "server:web"}}}"#
        XCTAssertNoThrow(try Wire.decode(AppRequest.self, from: Data(permission.utf8)))
    }

    func testHelperRequestFormat() throws {
        let json = String(decoding: try Wire.encode(HelperRequest.set(state: .orangeBlinkFast)), as: UTF8.self)
        XCTAssertEqual(json, #"{"set":{"state":"orange-blink-fast"}}"#)
    }

    func testHelperRejectsValuesOutsideWhitelist() {
        let data = Data(#"{"set":{"state":"purple"}}"#.utf8)
        XCTAssertThrowsError(try Wire.decode(HelperRequest.self, from: data))
    }

    func testFlashPatternIsClampedAndFinite() {
        XCTAssertEqual(LightPattern.flash(.green, times: 0).repeats, 1)
        XCTAssertEqual(LightPattern.flash(.green, times: 999).repeats, LightPattern.maxFlashCount)
        XCTAssertEqual(LightPattern.flash(.green, times: 3).duration, 1.5)
        XCTAssertNil(LightPattern.alternate.duration)
    }

    func testStatusSummary() {
        let status = AppStatus(
            light: "orange",
            pomodoro: PomodoroSnapshot(phase: .work, remainingSeconds: 125, isPaused: true, completedWorkSessions: 1)
        )
        XCTAssertEqual(status.summary, "light: orange\npomodoro: work 02:05 left (paused), 1 completed")
    }
}

final class UnixSocketTests: XCTestCase {
    func testRoundTripAndAuthorization() throws {
        let path = NSTemporaryDirectory() + "lamba-test-\(getpid()).sock"
        let server = try UnixSocketServer(
            path: path,
            permissions: 0o600,
            queue: DispatchQueue(label: "test"),
            authorize: { $0 == getuid() },
            handler: { Data("echo:".utf8) + $0 }
        )
        let reply = try UnixSocketClient.roundTrip(path: path, request: Data("hi".utf8))
        XCTAssertEqual(String(decoding: reply, as: UTF8.self), "echo:hi")

        let denied = try UnixSocketServer(
            path: path + "2",
            permissions: 0o600,
            queue: DispatchQueue(label: "test2"),
            authorize: { _ in false },
            handler: { $0 }
        )
        XCTAssertThrowsError(try UnixSocketClient.roundTrip(path: path + "2", request: Data("hi".utf8)))
        withExtendedLifetime((server, denied)) {}
    }

    func testMissingSocketIsReportedAsNotRunning() {
        XCTAssertThrowsError(try UnixSocketClient.roundTrip(path: "/tmp/lamba-does-not-exist.sock", request: Data("x".utf8))) {
            XCTAssertTrue(($0 as? SocketError)?.isNotRunning ?? false)
        }
    }
}

final class ChargeStateTests: XCTestCase {
    func testSystemStateResolvesToWhatMacOSShows() {
        XCTAssertEqual(LightState.system.resolved(for: .charging), .orange)
        XCTAssertEqual(LightState.system.resolved(for: .notCharging), .green)
        XCTAssertEqual(LightState.system.resolved(for: .onBattery), .off)
    }

    func testManualStatesAreUnchanged() {
        for state in LightState.allCases where state != .system {
            XCTAssertEqual(state.resolved(for: .charging), state)
        }
    }
}
