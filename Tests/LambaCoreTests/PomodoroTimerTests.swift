import XCTest
@testable import LambaCore

final class PomodoroTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let settings = PomodoroSettings(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, sessionsBeforeLongBreak: 2)

    func testStartsInWorkPhase() {
        let timer = PomodoroTimer(settings: settings, startingAt: t0)
        XCTAssertEqual(timer.phase, .work)
        XCTAssertEqual(timer.remaining(at: t0), 25 * 60)
        XCTAssertEqual(timer.snapshot(at: t0.addingTimeInterval(61)).formattedRemaining, "23:59")
    }

    func testTickBeforeDeadlineDoesNothing() {
        var timer = PomodoroTimer(settings: settings, startingAt: t0)
        XCTAssertNil(timer.tick(at: t0.addingTimeInterval(25 * 60 - 1)))
        XCTAssertEqual(timer.phase, .work)
    }

    func testWorkThenShortBreakThenLongBreak() {
        var timer = PomodoroTimer(settings: settings, startingAt: t0)
        var now = t0.addingTimeInterval(25 * 60)
        XCTAssertEqual(timer.tick(at: now), .shortBreak)
        XCTAssertEqual(timer.completedWorkSessions, 1)

        now += 5 * 60
        XCTAssertEqual(timer.tick(at: now), .work)

        now += 25 * 60
        XCTAssertEqual(timer.tick(at: now), .longBreak)
        XCTAssertEqual(timer.completedWorkSessions, 2)
        XCTAssertEqual(timer.remaining(at: now), 15 * 60)
    }

    func testPauseFreezesRemainingTime() {
        var timer = PomodoroTimer(settings: settings, startingAt: t0)
        timer.pause(at: t0.addingTimeInterval(60))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(3600)), 24 * 60)
        XCTAssertNil(timer.tick(at: t0.addingTimeInterval(3600)))

        let resumeAt = t0.addingTimeInterval(3600)
        timer.resume(at: resumeAt)
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: resumeAt), 24 * 60)
    }

    func testSkipAdvancesImmediately() {
        var timer = PomodoroTimer(settings: settings, startingAt: t0)
        XCTAssertEqual(timer.skip(at: t0), .shortBreak)
        XCTAssertEqual(timer.remaining(at: t0), 5 * 60)
    }

    func testSkipWhilePausedStaysPausedWithFullPhase() {
        var timer = PomodoroTimer(settings: settings, startingAt: t0)
        timer.pause(at: t0)
        timer.skip(at: t0)
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(999)), 5 * 60)
    }
}
