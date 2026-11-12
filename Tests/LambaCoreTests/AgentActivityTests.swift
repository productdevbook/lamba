import XCTest
@testable import LambaCore

final class AgentActivityTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testWaitingBeatsWorkingBeatsDone() {
        var activity = AgentActivity()
        activity.record(.done, session: "a", at: start)
        XCTAssertEqual(activity.summary(at: start), .done)
        activity.record(.working, session: "b", at: start)
        activity.record(.working, session: "c", at: start)
        XCTAssertEqual(activity.summary(at: start), .working(sessions: 2, detail: nil))
        activity.record(.waiting, session: "c", at: start)
        XCTAssertEqual(activity.summary(at: start), .waiting(sessions: 1))
    }

    func testDoneIconFadesButFinishedSessionStaysListed() {
        var activity = AgentActivity()
        activity.record(.done, session: nil, at: start)
        let later = start + AgentActivity.doneVisibleFor + 1
        XCTAssertNil(activity.summary(at: later))
        XCTAssertEqual(activity.sessions(at: later).map(\.event), [.done])
        XCTAssertTrue(activity.sessions(at: start + AgentActivity.staleAfter + 1).isEmpty)
    }

    func testStaleWorkingSessionsExpire() {
        var activity = AgentActivity()
        activity.record(.working, session: "a", at: start)
        XCTAssertEqual(activity.summary(at: start + 60), .working(sessions: 1, detail: nil))
        XCTAssertNil(activity.summary(at: start + AgentActivity.staleAfter + 1))
        XCTAssertTrue(activity.prune(at: start + AgentActivity.staleAfter + 1))
    }

    func testSameSessionReplacesItsState() {
        var activity = AgentActivity()
        activity.record(.working, session: "a", at: start)
        activity.record(.done, session: "a", at: start + 5)
        XCTAssertEqual(activity.summary(at: start + 6), .done)
    }

    func testWorkingShowsLatestDetail() {
        var activity = AgentActivity()
        activity.record(.working, session: "a", detail: AgentDetail(tool: "Read", target: "a.swift"), at: start)
        activity.record(.working, session: "b", detail: AgentDetail(tool: "Edit", target: "b.swift"), at: start + 1)
        XCTAssertEqual(activity.summary(at: start + 2), .working(sessions: 2, detail: AgentDetail(tool: "Edit", target: "b.swift")))
    }

    func testDetailFromHookInput() {
        XCTAssertEqual(AgentDetail(hookTool: "Edit", input: ["file_path": "/x/y/Dock.swift"]), AgentDetail(tool: "Edit", target: "Dock.swift"))
        XCTAssertEqual(AgentDetail(hookTool: "Bash", input: ["command": "swift test", "description": "Run tests"]).target, "Run tests")
        XCTAssertEqual(AgentDetail(hookTool: "WebFetch", input: ["url": "https://example.com/a"]).target, "example.com")
        let long = AgentDetail(hookTool: "Bash", input: ["command": String(repeating: "a", count: 100)]).target
        XCTAssertEqual(long?.count, AgentDetail.maxTargetLength)
    }

    func testSessionsKeepFirstSeenOrder() {
        var activity = AgentActivity()
        activity.record(.working, session: "b", at: start)
        activity.record(.working, session: "a", at: start + 1)
        activity.record(.waiting, session: "b", at: start + 2)
        XCTAssertEqual(activity.sessions(at: start + 3).map(\.id), ["b", "a"])
        XCTAssertEqual(activity.sessions(at: start + 3).first?.event, .waiting)
    }

    func testSessionTitlePrefersRenameThenLatestGeneratedTitle() {
        let lines = [
            #"{"type":"ai-title","aiTitle":"Old title"}"#,
            #"{"type":"user","message":"hi"}"#,
            #"{"type":"ai-title","aiTitle":"Charger LED"}"#,
        ]
        XCTAssertEqual(SessionTitle.parse(lines.joined(separator: "\n")), "Charger LED")
        let renamed = lines + [#"{"type":"custom-title","customTitle":"Lamba Dock"}"#, #"{"type":"ai-title","aiTitle":"Newer"}"#]
        XCTAssertEqual(SessionTitle.parse(renamed.joined(separator: "\n")), "Lamba Dock")
        XCTAssertNil(SessionTitle.parse(#"{"type":"user"}"#))
    }
}
