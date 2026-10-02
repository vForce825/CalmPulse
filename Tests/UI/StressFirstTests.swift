import XCTest
final class StressFirstTests: XCTestCase {
    @MainActor func testPrimaryStateAndDetailFlow() {
        let app = app(state: "steady"); app.launch()
        XCTAssertTrue(app.staticTexts["平稳"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today.breathing"].isHittable)
        XCTAssertFalse(app.staticTexts["SDNN"].exists)
        print("CALMPULSE_SCREENSHOT:phone-stress-steady:" + app.screenshot().pngRepresentation.base64EncodedString())
        app.buttons["stress.details"].tap()
        XCTAssertTrue(app.staticTexts["如何理解压力参考"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["today.breathing"].tap()
        XCTAssertTrue(app.buttons["breathing.start"].waitForExistence(timeout: 5))
        app.buttons["breathing.start"].tap()
        XCTAssertTrue(app.buttons["breathing.pauseResume"].waitForExistence(timeout: 5))
    }
    @MainActor func testAllStatesNeverInventCurrentReading() {
        for (state, title) in [("relaxed","较放松"),("tense","有些紧绷"),("high","压力偏高"),("learning","正在了解你"),("stale","等一条新记录"),("invalid","记录需要核对"),("unavailable","这次暂不判断")] {
            let app = app(state: state); app.launch()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), state)
            XCTAssertFalse(app.staticTexts["SDNN"].exists)
            print("CALMPULSE_SCREENSHOT:phone-stress-" + state + ":" + app.screenshot().pngRepresentation.base64EncodedString())
            app.terminate()
        }
    }
    @MainActor func testDarkLargeStateIsReadableAndScrollable() {
        let app = app(state: "high")
        app.launchEnvironment["CALMPULSE_DARK"] = "1"
        app.launchEnvironment["CALMPULSE_LARGE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["压力偏高"].waitForExistence(timeout: 10))
        print("CALMPULSE_SCREENSHOT:phone-stress-large-dark:" + app.screenshot().pngRepresentation.base64EncodedString())
        for _ in 0..<5 { if app.buttons["today.breathing"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["today.breathing"].isHittable)
    }
    @MainActor private func app(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"
        app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["CALMPULSE_DEMO_STATE"] = state
        return app
    }
}
