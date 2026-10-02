import XCTest
@testable import WellnessServices
final class SourceIdentityTests: XCTestCase {
    func testMissingDeviceIdentityCannotCombineSeparateRecordsIntoBaseline() {
        let first = SourceIdentity.key(bundle: "synthetic", localDeviceID: nil, sampleID: UUID())
        let second = SourceIdentity.key(bundle: "synthetic", localDeviceID: nil, sampleID: UUID())
        XCTAssertNotEqual(first, second)
    }
    func testKnownDeviceIdentityIsStableButReplacementIsSeparate() {
        XCTAssertEqual(SourceIdentity.key(bundle: "synthetic", localDeviceID: "A", sampleID: UUID()), SourceIdentity.key(bundle: "synthetic", localDeviceID: "A", sampleID: UUID()))
        XCTAssertNotEqual(SourceIdentity.key(bundle: "synthetic", localDeviceID: "A", sampleID: UUID()), SourceIdentity.key(bundle: "synthetic", localDeviceID: "B", sampleID: UUID()))
    }
}
