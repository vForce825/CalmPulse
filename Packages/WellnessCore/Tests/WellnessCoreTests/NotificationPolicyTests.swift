import Foundation
import XCTest
@testable import WellnessCore

final class NotificationPolicyTests: XCTestCase {
    private let policy = NotificationPolicy()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }
    private func assessment(hoursAgo: Double, score: Int? = 80, id: UUID = UUID(), source: String = "watch-A", freshness: DataFreshness = .fresh) -> WellnessAssessment {
        WellnessAssessment(score: score, baselineDayCount: 7, baselineSampleCount: 21, confidence: .limited, sourceID: source,
                           sampleID: id, observedAt: now.addingTimeInterval(-hoursAgo * 3600), freshness: freshness)
    }
    private var pair: [WellnessAssessment] { [assessment(hoursAgo: 2), assessment(hoursAgo: 1)] }
    private func decision(_ recent: [WellnessAssessment]? = nil, settings: NotificationSettings = NotificationSettings(enabled: true), lastSent: Date? = nil, now: Date? = nil, calendar: Calendar? = nil) -> NotificationDecision {
        policy.decision(recent: recent ?? pair, settings: settings, lastSentAt: lastSent, now: now ?? self.now, calendar: calendar ?? self.calendar)
    }
    func testEnabledOwnedPairSendsLatestSample() {
        let samples = pair
        XCTAssertEqual(decision(samples), .send(sampleID: samples[1].sampleID))
        XCTAssertTrue(decision(samples.reversed()).shouldSend)
    }
    func testDisabledAndWrongOwnerNeverSend() {
        XCTAssertEqual(decision(settings: NotificationSettings()), .suppress(.disabled))
        XCTAssertEqual(decision(settings: NotificationSettings(enabled: true, owner: .watch, evaluatingDevice: .iPhone)), .suppress(.wrongOwner))
        XCTAssertTrue(decision(settings: NotificationSettings(enabled: true, owner: .iPhone, evaluatingDevice: .iPhone)).shouldSend)
    }
    func testSingleDuplicateAndInsufficientScoresNeverSend() {
        let reading = assessment(hoursAgo: 1)
        XCTAssertFalse(decision([reading]).shouldSend)
        XCTAssertFalse(decision([reading, reading, reading]).shouldSend)
        XCTAssertFalse(decision([assessment(hoursAgo: 2), assessment(hoursAgo: 1, score: nil)]).shouldSend)
        XCTAssertFalse(decision([assessment(hoursAgo: 2), assessment(hoursAgo: 1, score: 74)]).shouldSend)
        XCTAssertTrue(decision([assessment(hoursAgo: 2, score: 75), assessment(hoursAgo: 1, score: 75)]).shouldSend)
    }
    func testLatestStaleAndFutureNeverSend() {
        XCTAssertFalse(decision([assessment(hoursAgo: 4), assessment(hoursAgo: 3.001)]).shouldSend)
        XCTAssertTrue(decision([assessment(hoursAgo: 4), assessment(hoursAgo: 3)]).shouldSend)
        XCTAssertFalse(decision([assessment(hoursAgo: 2), assessment(hoursAgo: 1, freshness: .historical)]).shouldSend)
        XCTAssertFalse(decision([assessment(hoursAgo: -2), assessment(hoursAgo: -1)]).shouldSend)
    }
    func testWindowSixHoursIncludesBoundaryButExcludesOlder() {
        XCTAssertTrue(decision([assessment(hoursAgo: 6), assessment(hoursAgo: 1)]).shouldSend)
        XCTAssertFalse(decision([assessment(hoursAgo: 6.001), assessment(hoursAgo: 1)]).shouldSend)
    }
    func testCooldownBoundaryAndNoReplayAfterCooldown() {
        XCTAssertFalse(decision(lastSent: now.addingTimeInterval(-7199)).shouldSend)
        XCTAssertTrue(decision(lastSent: now.addingTimeInterval(-7200)).shouldSend)
        XCTAssertEqual(decision([assessment(hoursAgo: 5), assessment(hoursAgo: 3)], lastSent: now.addingTimeInterval(-7200)), .suppress(.alreadySent))
    }
    func testSourcesCannotCombineForNotifications() {
        XCTAssertFalse(decision([assessment(hoursAgo: 2, source: "old-watch"), assessment(hoursAgo: 1)]).shouldSend)
    }
    func testQuietHoursExactBoundariesAndDST() {
        for (hour, expected) in [(7, false), (8, true), (21, true), (22, false), (23, false), (0, false)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: hour))!
            let samples = [date.addingTimeInterval(-1800), date.addingTimeInterval(-60)].map {
                WellnessAssessment(score: 80, sourceID: "watch-A", sampleID: UUID(), observedAt: $0)
            }
            XCTAssertEqual(decision(samples, now: date).shouldSend, expected, "hour \(hour)")
        }
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!
        let samples = [date.addingTimeInterval(-3600), date.addingTimeInterval(-60)].map {
            WellnessAssessment(score: 80, sourceID: "watch-A", sampleID: UUID(), observedAt: $0)
        }
        XCTAssertTrue(decision(samples, now: date, calendar: cal).shouldSend)
    }
    func testMalformedLastDeliveryTimeCannotQualify() {
        XCTAssertEqual(decision(lastSent: Date(timeIntervalSince1970: .nan)), .suppress(.invalidSettings))
    }

}
