import XCTest
final class OnboardingTests: XCTestCase {
    @MainActor func testNoDataOnboardingAndPrivacyExplanation() {
        let app = XCUIApplication()
        app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"; app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.readCore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["还没有可用记录"].exists)
        XCTAssertFalse(app.staticTexts["SDNN"].exists)
        print("CALMPULSE_SCREENSHOT:phone-today:" + app.screenshot().pngRepresentation.base64EncodedString())
        app.tabBars.buttons["设置"].tap()
        for _ in 0..<5 { if app.buttons["settings.clear"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["settings.clear"].exists)
        app.buttons["settings.clear"].tap()
        print("CALMPULSE_CLEAR_DIALOG:" + app.debugDescription)
        let cancel = app.buttons["取消"].waitForExistence(timeout: 3) ? app.buttons["取消"] : app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.buttons["settings.clear"].exists)
    }
}
