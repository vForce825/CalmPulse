import XCTest
import WellnessCore
@testable import WellnessServices
final class StressPresentationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func summary(_ score: Int? = 42, age: Double = 60, days: Int = 14, hidden: Bool = false) -> StoredSummary {
        StoredSummary(assessment: WellnessAssessment(score: score, baselineDayCount: days, baselineSampleCount: days * 3, confidence: days < 7 ? .insufficient : days < 14 ? .limited : .established, sourceID: "synthetic", sampleID: UUID(), observedAt: now.addingTimeInterval(-age)), sdnn: 40, sourceDevice: "test", hideValues: hidden)
    }
    func testFourBandsHavePlainLanguageAndNoRawMetrics() {
        for (score, title) in [(10,"较放松"),(35,"平稳"),(60,"有些紧绷"),(90,"压力偏高")] {
            let value = StressPresentation(summary: summary(score), now: now)
            XCTAssertEqual(value.title, title)
            XCTAssertEqual(value.state, .reading)
            XCTAssertFalse(value.explanation.contains("SDNN"))
            XCTAssertNotNil(value.bandIndex)
        }
    }
    func testFreshnessBoundaryRemovesCurrentBand() {
        XCTAssertEqual(StressPresentation(summary: summary(age: 10_800), now: now).state, .reading)
        let stale = StressPresentation(summary: summary(age: 10_801), now: now)
        XCTAssertEqual(stale.title, "等一条新记录")
        XCTAssertNil(stale.bandIndex)
        XCTAssertEqual(stale.state, .historical)
    }
    func testMissingLearningAndUnscorableAreDifferent() {
        XCTAssertEqual(StressPresentation(summary: nil, now: now).state, .missing)
        XCTAssertEqual(StressPresentation(summary: summary(nil, days: 3), now: now).state, .learning)
        XCTAssertEqual(StressPresentation(summary: summary(nil), now: now).state, .unavailable)
        XCTAssertEqual(StressPresentation(summary: summary(age: -60), now: now).state, .invalid)
    }
    func testPrivacyAndLockNeverExposeBand() {
        let hidden = StressPresentation(summary: summary(90, hidden: true), now: now, respectPrivacy: true)
        XCTAssertEqual(hidden.state, .hidden)
        XCTAssertNil(hidden.bandIndex)
        let locked = StressPresentation(summary: summary(90), now: now, status: .protected)
        XCTAssertEqual(locked.state, .locked)
        XCTAssertNil(locked.observedAt)
    }
    func testLimitedIsLabelledInitialReferenceNotAccuracy() {
        XCTAssertTrue(StressPresentation(summary: summary(35, days: 8), now: now).isInitial)
        XCTAssertFalse(StressPresentation(summary: summary(35), now: now).isInitial)
    }
    func testInsufficientHistoryNeverShowsCurrentBandEvenIfCachedScoreExists() {
        let value = StressPresentation(summary: summary(80, days: 3), now: now)
        XCTAssertEqual(value.state, .learning)
        XCTAssertNil(value.bandIndex)
    }
    func testHiddenInvalidRecordDoesNotRevealQualityState() {
        XCTAssertEqual(StressPresentation(summary: summary(age: -60, hidden: true), now: now, respectPrivacy: true).state, .hidden)
    }
    func testValidatedBandMappingRejectsAbsentAndOutOfRangeScores() {
        for score: Int? in [nil, -26, -1, 101, Int.max] { XCTAssertNil(StressPresentation.bandIndex(for: score)) }
        for (score, band) in [(0, 0), (24, 0), (25, 1), (49, 1), (50, 2), (74, 2), (75, 3), (100, 3)] {
            XCTAssertEqual(StressPresentation.bandIndex(for: score), band)
        }
    }
}
