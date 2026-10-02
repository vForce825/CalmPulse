import Foundation
import XCTest
@testable import WellnessCore

final class SleepAggregatorTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var start: Date { Date(timeIntervalSince1970: 0) }
    private var range: DateInterval { DateInterval(start: start, end: start.addingTimeInterval(86400)) }
    private func sleep(_ begin: Double, _ end: Double, stage: SleepStage? = nil, source: String = "A") -> HealthSample {
        HealthSample(id: UUID(), kind: .sleep, sourceID: source, start: start.addingTimeInterval(begin * 60), end: start.addingTimeInterval(end * 60), value: end - begin, sleepStage: stage)
    }
    func testOverlappingSourcesAndUUIDsAreUnioned() {
        let a = sleep(0, 60, source: "A"), b = sleep(30, 90, source: "B")
        let summary = SleepAggregator().summarize(samples: [a, a, b], range: range, calendar: cal)
        XCTAssertEqual(summary.availability, .available)
        XCTAssertEqual(summary.asleepMinutes, 90)
        XCTAssertEqual(summary.days.first?.asleepMinutes, 90)
    }
    func testStagesPresentAreRetainedWithoutDoubleCountingAndInBedIsSeparate() {
        let samples = [sleep(0, 120, stage: .inBed), sleep(10, 50, stage: .deep), sleep(50, 100, stage: .rem), sleep(100, 120, stage: .awake)]
        let summary = SleepAggregator().summarize(samples: samples, range: range, calendar: cal)
        XCTAssertEqual(summary.asleepMinutes, 90)
        XCTAssertEqual(summary.inBedMinutes, 120)
        XCTAssertEqual(summary.stages.first { $0.stage == .deep }?.minutes, 40)
        XCTAssertEqual(summary.stages.first { $0.stage == .rem }?.minutes, 50)
        let overlapping = SleepAggregator().summarize(samples: [sleep(0, 60, stage: .deep), sleep(0, 60, stage: .core, source: "B")], range: range, calendar: cal)
        XCTAssertEqual(overlapping.stages.reduce(0) { $0 + $1.minutes }, 60)
    }
    func testMidnightClippingAndDSTUseCivilDays() {
        let boundary = start.addingTimeInterval(86400)
        let sample = HealthSample(id: UUID(), kind: .sleep, sourceID: "A", start: boundary.addingTimeInterval(-1800), end: boundary.addingTimeInterval(1800), value: 60)
        let summary = SleepAggregator().summarize(samples: [sample], range: DateInterval(start: start, end: boundary.addingTimeInterval(86400)), calendar: cal)
        XCTAssertEqual(summary.days.map(\.asleepMinutes), [30, 30])
        XCTAssertEqual(SleepAggregator().summarize(samples: [sample], range: range, calendar: cal).asleepMinutes, 30)
        var local = cal; local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let a = local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!
        let b = local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4))!
        let dst = HealthSample(id: UUID(), kind: .sleep, sourceID: "A", start: a, end: b, value: 120)
        XCTAssertEqual(SleepAggregator().summarize(samples: [dst], range: DateInterval(start: a, end: b), calendar: local).asleepMinutes, 120)
    }
    func testEmptyAwakeOnlyAndInvalidIntervalsDoNotInventSleep() {
        XCTAssertEqual(SleepAggregator().summarize(samples: [], range: range, calendar: cal).availability, .unavailable)
        XCTAssertEqual(SleepAggregator().summarize(samples: [sleep(0, 60, stage: .awake)], range: range, calendar: cal).asleepMinutes, 0)
        XCTAssertEqual(SleepAggregator().summarize(samples: [sleep(60, 0)], range: range, calendar: cal).availability, .unavailable)
    }
}
