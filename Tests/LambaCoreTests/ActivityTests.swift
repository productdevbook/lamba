import XCTest
@testable import LambaCore

final class ActivityReportTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func focus(_ start: Date, minutes: Double, completed: Bool = true) -> ActivityRecord {
        ActivityRecord(kind: .focus, start: start, end: start.addingTimeInterval(minutes * 60),
                       value: completed ? ActivityRecord.completed : ActivityRecord.partial)
    }

    func testDailyFocusAndSessions() {
        let records = [
            focus(date(10, 9), minutes: 25),
            focus(date(12, 9), minutes: 25),
            focus(date(12, 10), minutes: 10, completed: false),
        ]
        let report = ActivityReport(records: records, dayCount: 3, now: date(12, 18), calendar: calendar)
        XCTAssertEqual(report.days.map { $0.focusSeconds / 60 }, [25, 0, 35])
        XCTAssertEqual(report.days.map(\.completedSessions), [1, 0, 1])
        XCTAssertEqual(report.completedSessions, 2)
        XCTAssertEqual(report.focusSeconds, 60 * 60)
    }

    func testFocusAcrossMidnightIsSplit() {
        let report = ActivityReport(records: [focus(date(11, 23, 50), minutes: 20)], dayCount: 2, now: date(12, 12), calendar: calendar)
        XCTAssertEqual(report.days.map { $0.focusSeconds / 60 }, [10, 10])
        XCTAssertEqual(report.days.map(\.completedSessions), [0, 1]) // counted on the day it ended
    }

    func testPreviousPeriodComparison() {
        let records = [focus(date(5, 9), minutes: 50), focus(date(11, 9), minutes: 25)]
        let report = ActivityReport(records: records, dayCount: 7, now: date(12, 12), calendar: calendar)
        XCTAssertEqual(report.previousFocusSeconds, 50 * 60)
        XCTAssertEqual(report.focusSeconds, 25 * 60)
    }

    func testStreakToleratesNoSessionYetToday() {
        let records = [focus(date(9, 9), minutes: 25), focus(date(10, 9), minutes: 25), focus(date(11, 9), minutes: 25)]
        XCTAssertEqual(ActivityReport(records: records, dayCount: 7, now: date(12, 8), calendar: calendar).streakDays, 3)
        let withGap = records + [focus(date(7, 9), minutes: 25)]
        XCTAssertEqual(ActivityReport(records: withGap, dayCount: 7, now: date(12, 8), calendar: calendar).streakDays, 3)
        XCTAssertEqual(ActivityReport(records: [], dayCount: 7, now: date(12, 8), calendar: calendar).streakDays, 0)
    }

    func testSharesAreClippedSortedAndIgnoreTinyValues() {
        let records = [
            ActivityRecord(kind: .light, start: date(1, 0), end: date(12, 2), value: "system"), // clipped to range
            ActivityRecord(kind: .light, start: date(12, 3), end: date(12, 4), value: "green"),
            ActivityRecord(kind: .light, start: date(12, 5), end: date(12, 5).addingTimeInterval(30), value: "orange"),
            ActivityRecord(kind: .flash, start: date(12, 6), end: date(12, 6), value: "green"),
        ]
        let report = ActivityReport(records: records, dayCount: 1, now: date(12, 12), calendar: calendar)
        XCTAssertEqual(report.light.map(\.name), ["system", "green"])
        XCTAssertEqual(report.light.first?.seconds, 2 * 3600)
        XCTAssertEqual(report.flashes, 1)
    }

    func testCSV() {
        let report = ActivityReport(records: [focus(date(12, 9), minutes: 25)], dayCount: 2, now: date(12, 12), calendar: calendar)
        XCTAssertEqual(report.csv(calendar: calendar), "date,focus_minutes,completed_sessions\n2026-11-11,0.0,0\n2026-11-12,25.0,1\n")
    }
}

final class ActivityStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lamba-activity-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testAppendLoadAndPrune() {
        let store = ActivityStore(url: url)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = ActivityRecord(kind: .flash, start: now.addingTimeInterval(-500 * 86_400), end: now.addingTimeInterval(-500 * 86_400), value: "green")
        let recent = ActivityRecord(kind: .flash, start: now, end: now, value: "orange")
        store.append(old)
        store.append(recent)
        XCTAssertEqual(store.load(), [old, recent])
        store.prune(now: now)
        XCTAssertEqual(store.load(), [recent])
    }

    func testSegmentRecorderClosesSegmentsAndDropsNoise() {
        var records: [ActivityRecord] = []
        let recorder = SegmentRecorder(kind: .light) { records.append($0) }
        let t0 = Date(timeIntervalSince1970: 1000)
        recorder.update("green", at: t0)
        recorder.update("green", at: t0.addingTimeInterval(5)) // same value: no-op
        recorder.update("orange", at: t0.addingTimeInterval(60))
        recorder.update("off", at: t0.addingTimeInterval(60.5)) // orange lasted 0.5s: dropped
        recorder.close(at: t0.addingTimeInterval(120))
        XCTAssertEqual(records.map(\.value), ["green", "off"])
        XCTAssertEqual(records.map(\.duration), [60, 59.5])
    }
}
