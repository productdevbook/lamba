import XCTest
@testable import LambaCore

private final class FakeService: LambaService {
    var received: [AppRequest] = []
    var response = AppResponse.success("done", status: AppStatus(light: "green", pomodoro: nil))

    func send(_ request: AppRequest) throws -> AppResponse {
        received.append(request)
        return response
    }
}

final class MCPServerTests: XCTestCase {
    private var service: FakeService!
    private var server: MCPServer!

    override func setUp() {
        service = FakeService()
        server = MCPServer(service: service)
    }

    private func call(_ json: String) throws -> [String: Any] {
        let reply = try XCTUnwrap(server.handle(json))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func toolCall(_ name: String, _ args: String) throws -> [String: Any] {
        let reply = try call(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(args)}}"#)
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    func testInitializeEchoesProtocolVersion() throws {
        let reply = try call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "lamba")
    }

    func testNotificationsGetNoReply() {
        XCTAssertNil(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testListsTools() throws {
        let reply = try call(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["set_light", "flash_light", "pomodoro", "vibrate", "get_report", "get_status"])
    }

    func testToolCallsMapToRequests() throws {
        _ = try toolCall("set_light", #"{"state":"orange"}"#)
        _ = try toolCall("flash_light", #"{"color":"green","times":5}"#)
        _ = try toolCall("pomodoro", #"{"action":"start","work_minutes":50}"#)
        _ = try toolCall("vibrate", #"{"times":4}"#)
        _ = try toolCall("get_report", #"{"days":30}"#)
        _ = try toolCall("get_status", "{}")

        XCTAssertEqual(service.received, [
            .set(state: .orange),
            .flash(color: .green, times: 5),
            .pomodoro(action: .start, settings: PomodoroSettings(workMinutes: 50)),
            .vibrate(times: 4),
            .report(days: 30),
            .status,
        ])
    }

    func testInvalidArgumentsAreToolErrors() throws {
        let result = try toolCall("set_light", #"{"state":"purple"}"#)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(service.received.isEmpty)
    }

    func testFlashRejectsNonColors() throws {
        let result = try toolCall("flash_light", #"{"color":"off"}"#)
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testUnknownMethod() throws {
        let reply = try call(#"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#)
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testParseError() throws {
        let reply = try call("not json")
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32700)
    }
}
