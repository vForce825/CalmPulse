import XCTest
@testable import WellnessCore
final class BuildConfigurationTests: XCTestCase {
    func testApprovedPlatformMinimums() {
        XCTAssertEqual(BuildConfiguration.iOSMinimum, "27.0")
        XCTAssertEqual(BuildConfiguration.watchOSMinimum, "27.0")
    }
}
