import XCTest
final class AccessibilityTests: XCTestCase {
    @MainActor func testDarkLargeTextNoDataFlowRemainsNavigable() {
        let app = XCUIApplication()
        app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"; app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["CALMPULSE_DARK"] = "1"
        app.launchEnvironment["CALMPULSE_LARGE"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 10))
        print("CALMPULSE_SCREENSHOT:phone-large-dark:" + app.screenshot().pngRepresentation.base64EncodedString())
        app.tabBars.buttons["习惯"].tap()
        XCTAssertTrue(app.buttons["habit.add.waterML"].waitForExistence(timeout: 5))
        app.buttons["habit.add.waterML"].tap()
        XCTAssertTrue(app.buttons["habit.save"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.tabBars.buttons["今日"].exists)
    }
}
