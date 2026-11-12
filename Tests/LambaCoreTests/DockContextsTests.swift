import XCTest
@testable import LambaCore

final class DockContextsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-12 is a Thursday (weekday 5).
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func env(_ date: Date, displays: [String] = [], wifi: String? = nil, front: String? = nil, mirroring: Bool = false) -> ContextEnvironment {
        ContextEnvironment(date: date, calendar: calendar, displayNames: displays, wifiSSID: wifi, frontBundleID: front, isMirroring: mirroring)
    }

    func testScheduleWithinDay() {
        let rule = ContextRule(trigger: .schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60))
        XCTAssertTrue(rule.matches(env(date(9))))
        XCTAssertTrue(rule.matches(env(date(17, 59))))
        XCTAssertFalse(rule.matches(env(date(18))))
        XCTAssertFalse(rule.matches(env(date(8, 59))))
        XCTAssertFalse(rule.matches(env(date(10, day: 14)))) // Saturday
    }

    func testScheduleAcrossMidnight() {
        let rule = ContextRule(trigger: .schedule(weekdays: Set(1...7), startMinute: 22 * 60, endMinute: 6 * 60))
        XCTAssertTrue(rule.matches(env(date(23))))
        XCTAssertTrue(rule.matches(env(date(5, 59))))
        XCTAssertFalse(rule.matches(env(date(12))))
    }

    func testOtherTriggersAndDisabledRules() {
        XCTAssertTrue(ContextRule(trigger: .display(name: "DELL U2723")).matches(env(date(12), displays: ["Built-in", "dell u2723"])))
        XCTAssertTrue(ContextRule(trigger: .wifi(ssid: "Office")).matches(env(date(12), wifi: "Office")))
        XCTAssertFalse(ContextRule(trigger: .wifi(ssid: "Office")).matches(env(date(12), wifi: nil)))
        XCTAssertTrue(ContextRule(trigger: .frontApp(bundleID: "com.apple.Keynote")).matches(env(date(12), front: "com.apple.Keynote")))
        XCTAssertTrue(ContextRule(trigger: .mirroring).matches(env(date(12), mirroring: true)))
        XCTAssertFalse(ContextRule(isEnabled: false, trigger: .mirroring).matches(env(date(12), mirroring: true)))
    }

    func testFirstMatchingContextWins() {
        let present = DockContext(name: "Present", color: .green, rules: [ContextRule(trigger: .mirroring)])
        let work = DockContext(name: "Work", color: .blue, rules: [ContextRule(trigger: .schedule(weekdays: Set(1...7), startMinute: 0, endMinute: 0))])
        XCTAssertEqual(ContextResolver.match([present, work], in: env(date(12), mirroring: true)), present.id)
        XCTAssertEqual(ContextResolver.match([present, work], in: env(date(12))), work.id)
        XCTAssertNil(ContextResolver.match([present], in: env(date(12))))
    }

    func testManualChoiceLastsUntilRulesChange() {
        let work = UUID(), home = UUID(), fallback = UUID()
        var selection = ContextSelection()
        XCTAssertEqual(selection.update(matched: nil, fallback: fallback), fallback)
        XCTAssertEqual(selection.update(matched: work, fallback: fallback), work)
        selection.choose(home)
        XCTAssertEqual(selection.update(matched: work, fallback: fallback), home) // same answer: keep the hand pick
        XCTAssertEqual(selection.update(matched: nil, fallback: fallback), fallback) // rules changed: they win
    }

    func testCodableRoundTrip() throws {
        let context = DockContext(
            name: "Work", color: .blue, appPaths: ["/Applications/Safari.app"],
            rules: [ContextRule(trigger: .schedule(weekdays: [2, 3], startMinute: 540, endMinute: 1080)), ContextRule(trigger: .mirroring)],
            look: ContextLook(wallpaper: "builtin:navy", appearance: .dark, flashColor: .green, shortcut: "Work Focus", hideApps: ["/Applications/Music.app"])
        )
        let decoded = try JSONDecoder().decode(DockContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(decoded, context)
    }
}
