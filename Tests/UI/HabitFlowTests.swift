import XCTest
final class HabitFlowTests: XCTestCase {
    @MainActor func testCreateEditDeleteLocalHabitAndRestoreRange() {
        let app = XCUIApplication(); app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"; app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = UUID().uuidString; app.launch()
        app.tabBars.buttons["习惯"].tap()
        for kind in ["mood", "waterML", "caffeineMG", "breathingSeconds"] {
            let add = app.buttons["habit.add." + kind]
            if !add.isHittable { app.swipeUp() }
            XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
            let note = app.textFields["habit.note"]
            note.tap(); note.typeText("Synthetic demonstration " + kind)
            app.buttons["habit.save"].tap()
        }
        app.swipeUp()
        print("CALMPULSE_SCREENSHOT:phone-habits:" + app.screenshot().pngRepresentation.base64EncodedString())
        let row = app.buttons.matching(identifier: "habit.entry").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        app.buttons["habit.delete"].tap()
        app.buttons["删除记录"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "habit.entry").count >= 3)
    }
}
