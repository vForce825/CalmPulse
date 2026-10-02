import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
final class WidgetFreshnessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)
    func summary(age: TimeInterval, hidden: Bool = false) -> StoredSummary {
        StoredSummary(assessment: WellnessAssessment(score: 85, baselineDayCount: 14, baselineSampleCount: 42, confidence: .established, sourceID: "synthetic", sampleID: UUID(), observedAt: now.addingTimeInterval(-age)), sdnn: 12, sourceDevice: "watch", hideValues: hidden)
    }
    func testStaleSummaryIsHistoricalAndNextTransitionScheduled() {
        let fresh = WidgetState(summary: summary(age: 60), now: now, protectedDataAvailable: true)
        XCTAssertEqual(fresh.label, "压力偏高")
        XCTAssertNotNil(fresh.nextTransition)
        let stale = WidgetState(summary: summary(age: 10801), now: now, protectedDataAvailable: true)
        XCTAssertEqual(stale.label, "等一条新记录")
        XCTAssertEqual(stale.score, 85)
        XCTAssertNil(stale.presentation.bandIndex)
        XCTAssertEqual(stale.presentation.state, .historical)
        XCTAssertNil(stale.nextTransition)
        let boundary = WidgetState(summary: summary(age: 10800), now: now, protectedDataAvailable: true)
        XCTAssertEqual(boundary.presentation.state, .reading)
        XCTAssertEqual(boundary.nextTransition, now.addingTimeInterval(1))
    }
    func testProtectedAndHiddenNeverHaveNumericValue() {
        let locked = WidgetState(summary: summary(age: 0), now: now, protectedDataAvailable: false)
        XCTAssertNil(locked.score); XCTAssertNil(locked.sdnn)
        XCTAssertEqual(locked.label, "解锁后查看")
        let hidden = WidgetState(summary: summary(age: 0, hidden: true), now: now, protectedDataAvailable: true)
        XCTAssertNil(hidden.score); XCTAssertNil(hidden.sdnn)
        XCTAssertEqual(hidden.label, "状态已隐藏")
        XCTAssertNil(hidden.observedAt)
        XCTAssertNil(hidden.nextTransition)
    }
}
extension WidgetFreshnessTests {
    func testFutureTimestampIsNeverPresentedAsCurrentValue() {
        let state = WidgetState(summary: summary(age: -60), now: now, protectedDataAvailable: true)
        XCTAssertNil(state.score); XCTAssertNil(state.sdnn); XCTAssertNil(state.nextTransition)
        XCTAssertEqual(state.label, "记录需要核对")
    }
}

extension WidgetFreshnessTests {
    func testMissingRecordNeverImpliesAStressBand() {
        let missing = WidgetState(summary: nil, now: now, protectedDataAvailable: true)
        XCTAssertEqual(missing.label, "还没有可用记录")
        XCTAssertNil(missing.score)
        XCTAssertNil(missing.observedAt)
    }
    func testFourPlainLanguageBandsMatchSharedPresentation() {
        for (score, title) in [(10, "较放松"), (35, "平稳"), (60, "有些紧绷"), (90, "压力偏高")] {
            let source = StoredSummary(assessment: WellnessAssessment(score: score, baselineDayCount: 14, baselineSampleCount: 42, confidence: .established, sourceID: "synthetic", sampleID: UUID(), observedAt: now.addingTimeInterval(-60)), sdnn: 12, sourceDevice: "watch", hideValues: false)
            let state = WidgetState(summary: source, now: now, protectedDataAvailable: true)
            XCTAssertEqual(state.label, title)
            XCTAssertEqual(state.presentation.bandIndex, score / 25)
        }
    }
}
