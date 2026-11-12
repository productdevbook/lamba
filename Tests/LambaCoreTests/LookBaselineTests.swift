import XCTest
@testable import LambaCore

final class LookBaselineTests: XCTestCase {
    func testCaptureKeepsFirstValue() {
        var baseline = LookBaseline()
        baseline.captureWallpaper(displayKey: "1", current: "file:///a.png")
        baseline.captureWallpaper(displayKey: "1", current: "file:///b.png")
        baseline.captureAppearance(isDark: false)
        baseline.captureAppearance(isDark: true)
        XCTAssertEqual(baseline.wallpapers["1"], "file:///a.png")
        XCTAssertEqual(baseline.darkMode, false)
    }

    func testAppearancePlan() {
        XCTAssertEqual(LookPlanner.appearance(nil, baseline: LookBaseline()), .leave)
        XCTAssertEqual(LookPlanner.appearance(.dark, baseline: LookBaseline()), .set(true))
        XCTAssertEqual(LookPlanner.appearance(nil, baseline: LookBaseline(darkMode: false)), .restore(false))
    }

    func testWallpaperPlan() {
        let baseline = LookBaseline(wallpapers: ["1": "file:///a.png"])
        XCTAssertEqual(LookPlanner.wallpaper(nil, displayKey: "2", baseline: baseline), .leave)
        XCTAssertEqual(LookPlanner.wallpaper(nil, displayKey: "1", baseline: baseline), .restore("file:///a.png"))
        XCTAssertEqual(LookPlanner.wallpaper("x", displayKey: "1", baseline: baseline), .set("x"))
    }

    func testDefaultContexts() {
        let result = DefaultContexts.make(names: .init(work: "W", personal: "P", presenting: "R"), appPaths: ["/A.app"])
        XCTAssertEqual(result.contexts.map(\.name), ["W", "P", "R"])
        XCTAssertEqual(result.defaultID, result.contexts[1].id)
        XCTAssertTrue(result.contexts[1].rules.isEmpty)
        XCTAssertTrue(result.contexts.allSatisfy { $0.look == ContextLook() })
    }
}
