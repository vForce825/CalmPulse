import XCTest
@testable import WellnessServices
final class HealthRepositoryTests: XCTestCase {
    func testNoReadRecordsIsNeutral() { XCTAssertEqual(HealthDataStatus.empty.message, "暂未读到记录") }
}
