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
extension SourceIdentityTests {
    func testObservedNativeWatchUUIDFallbackGroupsOnlyIdentifiedNativeSources() {
        let bundle = "com.apple.health.11111111-2222-3333-4444-555555555555"
        func key(_ bundle: String, watch: Bool = true, hardware: String = "Watch6,4") -> String {
            SourceIdentity.key(bundle: bundle, localDeviceID: nil, sampleID: UUID(), isAppleWatch: watch, hardware: hardware)
        }
        XCTAssertEqual(key(bundle), key(bundle))
        XCTAssertNotEqual(key(bundle), key("com.apple.health.11111111-2222-3333-4444-555555555556"))
        XCTAssertNotEqual(key(bundle), key(bundle, hardware: "Watch7,1"))
        for unknown in ["com.apple.health", "com.apple.health.invalid", "third.party.watch"] { XCTAssertNotEqual(key(unknown), key(unknown)) }
        XCTAssertNotEqual(key(bundle, watch: false), key(bundle, watch: false))
        let local = SourceIdentity.key(bundle: bundle, localDeviceID: "local-A", sampleID: UUID(), isAppleWatch: true)
        XCTAssertEqual(local, bundle + "|local-A")
    }
}
