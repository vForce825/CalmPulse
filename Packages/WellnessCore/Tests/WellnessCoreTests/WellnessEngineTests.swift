import Foundation
import XCTest
@testable import WellnessCore

final class WellnessEngineTests: XCTestCase {
    private let engine = WellnessEngine()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }
    private func sample(_ value: Double, at date: Date, source: String = "watch-A", kind: MetricKind = .sdnn, id: UUID = UUID()) -> HealthSample {
        HealthSample(id: id, kind: kind, sourceID: source, start: date, end: date, value: value)
    }
    private func history(days: Int = 7, values: [Double] = [10, 20, 30], calendar: Calendar? = nil, date: Date? = nil) -> [HealthSample] {
        let cal = calendar ?? self.calendar
        let day = cal.startOfDay(for: date ?? now)
        return (1...max(1, days)).flatMap { offset in
            values.enumerated().map { index, value in
                sample(value, at: cal.date(byAdding: .day, value: -offset, to: day)!.addingTimeInterval(Double(index + 1) * 3600))
            }
        }
    }
    private func assess(_ value: Double, history: [HealthSample]? = nil, workouts: [WorkoutWindow] = [], source: String = "watch-A") -> WellnessAssessment {
        engine.assess(current: sample(value, at: now, source: source), history: history ?? self.history(), workouts: workouts, calendar: calendar, now: now)
    }

    func testMidrankAndExtremeScores() {
        XCTAssertEqual(assess(20).score, 50)
        XCTAssertEqual(assess(40).score, 0)
        XCTAssertEqual(assess(5).score, 100)
        XCTAssertEqual(assess(20).band, .high)
    }
    func testBaselineRequiresSevenDaysAndTwentySamples() {
        XCTAssertNil(assess(20, history: history(days: 6)).score)
        XCTAssertNil(assess(20, history: Array(history().dropLast(2))).score)
        XCTAssertEqual(assess(20, history: Array(history().dropLast())).baselineSampleCount, 20)
        XCTAssertEqual(assess(20).confidence, .limited)
        XCTAssertEqual(assess(20, history: history(days: 14)).confidence, .established)
    }
    func testDifferentSourcesAndRestingHeartRateNeverEnterBaseline() {
        let unrelated = history(days: 28, values: [1, 2, 3]).map { sample($0.value, at: $0.start, source: "watch-B") }
        let rhr = history(days: 28, values: [1, 2, 3]).map { sample($0.value, at: $0.start, kind: .restingHeartRate) }
        let result = assess(20, history: history() + unrelated + rhr)
        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.baselineSampleCount, 21)
        XCTAssertNil(assess(20, history: history(), source: "watch-B").score)
    }
    func testTodayAndOlderThanTwentyEightCivilDaysAreExcluded() {
        let today = (0..<20).map { sample(1, at: now.addingTimeInterval(-Double($0 + 1))) }
        let old = sample(1, at: calendar.date(byAdding: .day, value: -29, to: now)!)
        let result = assess(20, history: history() + today + [old])
        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.baselineDayCount, 7)
        XCTAssertEqual(result.baselineSampleCount, 21)
        XCTAssertEqual(result.baselineRange?.end, calendar.startOfDay(for: now))
    }
    func testDaysHaveEqualWeightDespiteUnequalSampleCounts() {
        let crowdedDay = calendar.date(byAdding: .day, value: -1, to: now)!
        let extras = (0..<10).map { sample(10, at: crowdedDay.addingTimeInterval(Double($0))) }
        XCTAssertEqual(assess(20, history: history() + extras).score, 45)
    }
    func testDuplicateUUIDsAreIdempotent() {
        let original = history()
        let result = assess(20, history: original + original + original)
        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.baselineSampleCount, 21)
    }
    func testNonFiniteZeroNegativeAndInvalidIntervalsAreRejected() {
        for value in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(assess(value).score)
        }
        let invalid = [0, -1, Double.nan, Double.infinity].map { sample($0, at: calendar.date(byAdding: .day, value: -1, to: now)!) }
        XCTAssertEqual(assess(20, history: history() + invalid).baselineSampleCount, 21)
        let backward = HealthSample(id: UUID(), kind: .sdnn, sourceID: "watch-A", start: now, end: now.addingTimeInterval(-1), value: 20)
        XCTAssertNil(engine.assess(current: backward, history: history(), workouts: [], calendar: calendar, now: now).score)
        let rhr = sample(20, at: now, kind: .restingHeartRate)
        XCTAssertNil(engine.assess(current: rhr, history: history(), workouts: [], calendar: calendar, now: now).score)
    }
    func testWorkoutAndThirtyMinuteTailAreExcludedInclusively() {
        let recent = WorkoutWindow(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800))
        XCTAssertNil(assess(20, workouts: [recent]).score)
        let ended = WorkoutWindow(start: now.addingTimeInterval(-3601), end: now.addingTimeInterval(-1801))
        XCTAssertEqual(assess(20, workouts: [ended]).score, 50)
        let blocked = history().first!
        let historicalWorkout = WorkoutWindow(start: blocked.start.addingTimeInterval(-60), end: blocked.end)
        XCTAssertEqual(assess(20, workouts: [historicalWorkout]).baselineSampleCount, 20)
    }
    func testFreshnessExactThreeHoursBoundaryAndFutureSample() {
        let current = sample(20, at: now)
        let fresh = engine.assess(current: current, history: history(), workouts: [], calendar: calendar, now: now.addingTimeInterval(10800))
        let historical = engine.assess(current: current, history: history(), workouts: [], calendar: calendar, now: now.addingTimeInterval(10801))
        XCTAssertEqual(fresh.freshness, .fresh)
        XCTAssertEqual(historical.freshness, .historical)
        XCTAssertEqual(historical.version, "wellness-sdnn-v1")
        XCTAssertEqual(historical.sampleID, current.id)
        XCTAssertEqual(historical.observedAt, current.start)
        XCTAssertNil(engine.assess(current: current, history: history(), workouts: [], calendar: calendar, now: now.addingTimeInterval(-1)).score)
    }
    func testDSTSpringAndFallHaveUniqueCivilDays() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for components in [DateComponents(year: 2026, month: 3, day: 12, hour: 12), DateComponents(year: 2026, month: 11, day: 5, hour: 12)] {
            let date = cal.date(from: components)!
            let baseline = history(days: 7, calendar: cal, date: date)
            let result = engine.assess(current: sample(20, at: date), history: baseline, workouts: [], calendar: cal, now: date)
            XCTAssertEqual(result.score, 50)
            XCTAssertEqual(result.baselineDayCount, 7)
            XCTAssertEqual(result.baselineSampleCount, 21)
        }
    }
}
