import XCTest

/// Uses only the app's explicitly empty, synthetic demonstration repository.
final class TrendsTests: XCTestCase {
    private let testNamespace = UUID().uuidString
    @MainActor func testRangeSelectionRestoresAfterRelaunchAndHistoryIsNavigable() {
        let app = demonstrationApp()
        app.launch()
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["trend.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trend.previous"].exists)
        XCTAssertTrue(app.buttons["trend.chooseDate"].exists)
        app.buttons["月"].tap()
        let selection = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: app.buttons["月"])
        wait(for: [selection], timeout: 5)
        app.buttons["trend.previous"].tap()
        app.buttons["trend.chooseDate"].tap()
        XCTAssertTrue(app.datePickers["trend.datePicker"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.buttons["月"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["月"].isSelected)
    }

    @MainActor func testHealthSectionsExplainOptionalReadingBeforeRequestingIt() {
        let app = demonstrationApp()
        app.launch()
        app.tabBars.buttons["习惯"].tap()
        let overview = app.buttons["health.overview"]
        if !overview.isHittable { app.swipeUp() }
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        overview.tap()
        XCTAssertTrue(app.staticTexts["health.sleep.explanation"].exists)
        XCTAssertTrue(app.buttons["health.request.sleep"].exists)
        app.buttons["health.request.sleep"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["health.sleep.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["health.request.sleep"].exists)
        XCTAssertFalse(app.staticTexts["已拒绝授权"].exists)
    }

    private func demonstrationApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"
        app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = testNamespace
        return app
    }
}
