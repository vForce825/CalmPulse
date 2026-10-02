import Foundation
import XCTest
@testable import WellnessCore

final class ModelsTests: XCTestCase {
    func testSampleAndHabitPublicContractsRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let sample = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-watch", start: date, end: date, value: 20)
        XCTAssertEqual(try JSONDecoder().decode(HealthSample.self, from: JSONEncoder().encode(sample)), sample)
        let habit = HabitEntry(id: UUID(), kind: .waterML, timestamp: date, value: 250, note: nil, revision: 1, origin: "phone", deleted: false)
        XCTAssertEqual(try JSONDecoder().decode(HabitEntry.self, from: JSONEncoder().encode(habit)), habit)
    }

    func testNotificationDefaultsAreDisabledAndWatchOwned() {
        let settings = NotificationSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.owner, .watch)
        XCTAssertEqual(settings.evaluatingDevice, .watch)
    }

    func testBandBoundariesAndSourceContext() {
        XCTAssertEqual(WellnessBand(score: 0), .low)
        XCTAssertEqual(WellnessBand(score: 24), .low)
        XCTAssertEqual(WellnessBand(score: 25), .moderate)
        XCTAssertEqual(WellnessBand(score: 49), .moderate)
        XCTAssertEqual(WellnessBand(score: 50), .high)
        XCTAssertEqual(WellnessBand(score: 74), .high)
        XCTAssertEqual(WellnessBand(score: 75), .highest)
        XCTAssertEqual(WellnessBand(score: 100), .highest)
        XCTAssertNil(WellnessBand(score: -1))
        XCTAssertNil(WellnessBand(score: 101))
        let date = Date(timeIntervalSince1970: 1_000)
        let sleep = HealthSample(id: UUID(), kind: .sleep, sourceID: "synthetic-watch", start: date, end: date.addingTimeInterval(60), value: 1, sleepStage: .deep)
        XCTAssertEqual(sleep.sleepStage, .deep)
        XCTAssertFalse(sleep.isAppleWatch)
    }
}
