import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
final class WidgetFreshnessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000)
    func summary(age: TimeInterval, hidden: Bool = false) -> StoredSummary {
        StoredSummary(assessment: WellnessAssessment(score: 85, sourceID: "synthetic", sampleID: UUID(), observedAt: now.addingTimeInterval(-age)), sdnn: 12, sourceDevice: "watch", hideValues: hidden)
    }
    func testStaleSummaryIsHistoricalAndNextTransitionScheduled() {
        let fresh = WidgetState(summary: summary(age: 60), now: now, protectedDataAvailable: true)
        XCTAssertEqual(fresh.label, "最近读数")
        XCTAssertNotNil(fresh.nextTransition)
        let stale = WidgetState(summary: summary(age: 10801), now: now, protectedDataAvailable: true)
        XCTAssertEqual(stale.label, "历史读数")
        XCTAssertEqual(stale.score, 85)
    }
    func testProtectedAndHiddenNeverHaveNumericValue() {
        let locked = WidgetState(summary: summary(age: 0), now: now, protectedDataAvailable: false)
        XCTAssertNil(locked.score); XCTAssertNil(locked.sdnn)
        XCTAssertEqual(locked.label, "解锁后查看")
        let hidden = WidgetState(summary: summary(age: 0, hidden: true), now: now, protectedDataAvailable: true)
        XCTAssertNil(hidden.score); XCTAssertNil(hidden.sdnn)
    }
}
