import Foundation
import XCTest
@testable import WellnessCore

final class ActivitySummaryTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let start = Date(timeIntervalSince1970: 0)
    private func sample(_ kind: MetricKind, _ value: Double, offset: Double = 0, duration: Double = 0, source: String = "A") -> HealthSample {
        HealthSample(id: UUID(), kind: kind, sourceID: source, start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + duration), value: value, workoutType: kind == .workout ? "walking" : nil)
    }
    func testNoConfiguredZonesShowsRawWorkoutAndHeartRate() {
        let samples = [sample(.workout, 30, duration: 1800), sample(.heartRate, 100, offset: 60), sample(.heartRate, 140, offset: 120)]
        let result = ActivitySummary().summarize(samples: samples, range: DateInterval(start: start, end: start.addingTimeInterval(3600)), calendar: cal)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertEqual(result.workouts.first?.durationMinutes, 30)
        XCTAssertEqual(result.workouts.first?.heartRateSampleCount, 2)
        XCTAssertEqual(result.workouts.first?.meanHeartRate, 120)
        XCTAssertTrue(result.workouts.first?.zones.isEmpty == true)
    }
    func testExplicitZoneBoundariesAndSamplingGaps() {
        XCTAssertNil(HeartRateZoneConfiguration(boundaries: [140, 100]))
        XCTAssertNil(HeartRateZoneConfiguration(boundaries: [100, 100]))
        XCTAssertNil(HeartRateZoneConfiguration(boundaries: [Double.nan]))
        let zones = HeartRateZoneConfiguration(boundaries: [100, 140])!
        let samples = [sample(.workout, 30, duration: 1800), sample(.heartRate, 100, offset: 0), sample(.heartRate, 140, offset: 60), sample(.heartRate, 160, offset: 120), sample(.heartRate, 90, offset: 900)]
        let result = ActivitySummary().summarize(samples: samples, range: DateInterval(start: start, end: start.addingTimeInterval(1800)), calendar: cal, zones: zones)
        XCTAssertEqual(result.workouts.first?.zones.first { $0.index == 1 }?.minutes, 1)
        XCTAssertEqual(result.workouts.first?.zones.first { $0.index == 2 }?.minutes, 1)
        XCTAssertEqual(result.workouts.first?.zones.reduce(0) { $0 + $1.minutes }, 2)
    }
    func testActivityTotalsSplitCivilMidnightAndKeepMissingNil() {
        let samples = [sample(.steps, 100, offset: 86340, duration: 120), sample(.activeEnergy, 50), sample(.exerciseMinutes, 20), sample(.daylightMinutes, 10), sample(.mindfulnessMinutes, 5)]
        let result = ActivitySummary().summarize(samples: samples, range: DateInterval(start: start, end: start.addingTimeInterval(172800)), calendar: cal)
        XCTAssertEqual(result.daily.map(\.steps), [50, 50])
        XCTAssertEqual(result.daily.first?.activeEnergyKCAL, 50)
        XCTAssertEqual(result.daily.first?.exerciseMinutes, 20)
        XCTAssertEqual(result.daily.first?.daylightMinutes, 10)
        XCTAssertEqual(result.daily.first?.mindfulnessMinutes, 5)
        XCTAssertNil(result.daily.last?.activeEnergyKCAL)
    }
    func testDuplicateSamplesAndMultipleSourcesAreNotAddedTogether() {
        let a = sample(.steps, 100), b = sample(.steps, 100, source: "B")
        let result = ActivitySummary().summarize(samples: [a, a, b], range: DateInterval(start: start, end: start.addingTimeInterval(86400)), calendar: cal)
        XCTAssertEqual(result.daily.first?.steps, 100)
        XCTAssertEqual(result.sourceIDs[.steps], "A")
        XCTAssertEqual(ActivitySummary().summarize(samples: [], range: DateInterval(start: start, end: start.addingTimeInterval(86400)), calendar: cal).availability, .unavailable)
    }
}
