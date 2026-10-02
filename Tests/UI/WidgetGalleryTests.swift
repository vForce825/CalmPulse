import XCTest
final class WidgetGalleryTests: XCTestCase {
    @MainActor func testSharedWidgetContentRendersSyntheticStates() {
        let app = XCUIApplication()
        app.launchEnvironment["CALMPULSE_UI_TESTING"] = "1"
        app.launchEnvironment["CALMPULSE_UI_TEST_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["CALMPULSE_WIDGET_GALLERY"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["widget.gallery"].waitForExistence(timeout: 10))
        print("CALMPULSE_SCREENSHOT:widget-content-gallery:" + app.screenshot().pngRepresentation.base64EncodedString())
    }
}
