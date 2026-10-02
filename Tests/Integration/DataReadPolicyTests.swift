import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices

final class DataReadPolicyTests: XCTestCase, @unchecked Sendable {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func sample(_ kind: MetricKind, start: Date, value: Double = 1, source: String = "source") -> HealthSample {
        HealthSample(id: UUID(), kind: kind, sourceID: source, start: start, end: start, value: value)
    }
    private func store() -> HistoryStore {
        HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testPhoneCompleteHistoryKindsHaveNoReadCutoff() {
        let now = date("2026-10-02T10:00:00Z")
        for kind in [MetricKind.sdnn, .restingHeartRate, .sleep, .mindfulnessMinutes, .workout] {
            XCTAssertNil(DataReadPolicy.retentionStart(for: kind, on: .iPhone, now: now, calendar: calendar))
        }
    }
    func testHeartRateAndWatchUseNinetyCalendarDaysAcrossDST() {
        let now = date("2026-05-02T10:00:00Z")
        let expected = calendar.date(byAdding: .day, value: -90, to: now)!
        XCTAssertEqual(DataReadPolicy.retentionStart(for: .heartRate, on: .iPhone, now: now, calendar: calendar), expected)
        for kind in MetricKind.allCases where kind != .workout {
            XCTAssertEqual(DataReadPolicy.retentionStart(for: kind, on: .watch, now: now, calendar: calendar), expected)
        }
        XCTAssertNotEqual(now.timeIntervalSince(expected), 90 * 24 * 60 * 60)
    }
    func testWatchWorkoutReadIncludesTheThirtyMinuteExclusionLookback() {
        let now = date("2026-05-02T10:00:00Z")
        let cutoff = calendar.date(byAdding: .day, value: -90, to: now)!
        XCTAssertEqual(DataReadPolicy.retentionStart(for: .workout, on: .watch, now: now, calendar: calendar), cutoff.addingTimeInterval(-30 * 60))
        XCTAssertNil(DataReadPolicy.retentionStart(for: .workout, on: .iPhone, now: now, calendar: calendar))
    }
    func testTransientDetailRangeIncludesStartAndExcludesEndWithoutPadding() {
        let start = date("2026-10-02T10:00:00Z")
        let range = DateInterval(start: start, duration: 300)
        let before = sample(.heartRate, start: start.addingTimeInterval(-1))
        let first = sample(.heartRate, start: start)
        let last = sample(.heartRate, start: range.end.addingTimeInterval(-1))
        let after = sample(.heartRate, start: range.end)
        XCTAssertEqual(DataReadPolicy.samples([before, first, last, after], within: range), [first, last])
        XCTAssertTrue(DataReadPolicy.samples([first], within: DateInterval(start: start, duration: 0)).isEmpty)
    }
    func testOnlyCumulativeActivityKindsUseDailyStatistics() {
        XCTAssertEqual(Set(MetricKind.allCases.filter(DataReadPolicy.usesDailyStatistics)), [.steps, .activeEnergy, .exerciseMinutes, .daylightMinutes])
    }
    func testAggregateIDsAreStableAndSeparateMetricSourceAndDay() {
        let day = calendar.startOfDay(for: date("2026-10-02T10:00:00Z"))
        let first = DataReadPolicy.aggregateID(kind: .steps, sourceID: "watch", dayStart: day)
        XCTAssertEqual(first.uuidString, "3628C407-A8B8-891E-8D1C-E09E0A9710B7")
        XCTAssertEqual(first, DataReadPolicy.aggregateID(kind: .steps, sourceID: "watch", dayStart: day))
        XCTAssertNotEqual(first, DataReadPolicy.aggregateID(kind: .activeEnergy, sourceID: "watch", dayStart: day))
        XCTAssertNotEqual(first, DataReadPolicy.aggregateID(kind: .steps, sourceID: "phone", dayStart: day))
        XCTAssertNotEqual(first, DataReadPolicy.aggregateID(kind: .steps, sourceID: "watch", dayStart: calendar.date(byAdding: .day, value: 1, to: day)!))
    }
    func testDailyAggregateIsAPointWithoutInventedWithinDayDistribution() throws {
        let day = calendar.startOfDay(for: date("2026-10-02T10:00:00Z"))
        let total = try XCTUnwrap(DataReadPolicy.dailyAggregate(kind: .steps, sourceID: "source", sourceName: "Source", dayStart: day, value: 1200))
        XCTAssertEqual(total.start, day)
        XCTAssertEqual(total.end, day)
        let range = DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!)
        let report = ActivitySummary().summarize(samples: [total], range: range, calendar: calendar)
        XCTAssertEqual(report.daily.first?.steps, 1200)
        XCTAssertEqual(report.sourceIDs[.steps], "source")
        XCTAssertFalse(total.isAppleWatch, "Statistics source alone cannot establish a Watch device")
        XCTAssertNil(DataReadPolicy.dailyAggregate(kind: .sdnn, sourceID: "source", sourceName: nil, dayStart: day, value: 50))
        XCTAssertNil(DataReadPolicy.dailyAggregate(kind: .steps, sourceID: "source", sourceName: nil, dayStart: day, value: .nan))
        XCTAssertNil(DataReadPolicy.dailyAggregate(kind: .steps, sourceID: "source", sourceName: nil, dayStart: day, value: -1))
    }
    func testAggregateSourcesStaySeparateAndNeverBlendSDNNBaseline() throws {
        let day = calendar.startOfDay(for: date("2026-10-02T10:00:00Z"))
        let a = try XCTUnwrap(DataReadPolicy.dailyAggregate(kind: .steps, sourceID: "a", sourceName: "A", dayStart: day, value: 1200))
        let b = try XCTUnwrap(DataReadPolicy.dailyAggregate(kind: .steps, sourceID: "b", sourceName: "B", dayStart: day, value: 3000))
        let report = ActivitySummary().summarize(samples: [a, b], range: DateInterval(start: day, duration: 86400), calendar: calendar)
        XCTAssertEqual(report.daily.first?.steps, 1200)
        XCTAssertEqual(report.sourceIDs[.steps], "a")
        XCTAssertNotEqual(a.id, b.id)
        let first = SourceIdentity.key(for: .sdnn, bundle: "bundle", localDeviceID: "watch-a", sampleID: UUID())
        let second = SourceIdentity.key(for: .sdnn, bundle: "bundle", localDeviceID: "watch-b", sampleID: UUID())
        XCTAssertNotEqual(first, second)
    }
    func testCompleteAggregateReplacementRemovesDeletedAndZeroRecordDaysAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = HistoryStore(directory: directory)
        let yesterday = date("2026-10-01T00:00:00Z"), today = date("2026-10-02T00:00:00Z")
        let old = sample(.steps, start: yesterday, value: 100)
        let obsoleteSource = sample(.steps, start: today, value: 200, source: "removed-source")
        let sdnn = sample(.sdnn, start: yesterday, value: 40)
        try await storage.apply(HealthChanges(kind: .steps, inserted: [old, obsoleteSource], newAnchor: Data([1])))
        try await storage.apply(HealthChanges(kind: .sdnn, inserted: [sdnn], newAnchor: Data([2])))
        let fresh = sample(.steps, start: today, value: 50)
        try await storage.apply(HealthChanges(kind: .steps, inserted: [fresh], replacesKind: true))
        var state = try await storage.snapshot()
        XCTAssertEqual(state.samples.filter { $0.kind == .steps }, [fresh])
        XCTAssertEqual(state.samples.filter { $0.kind == .sdnn }, [sdnn])
        XCTAssertNil(state.anchors[.steps])
        XCTAssertEqual(state.anchors[.sdnn], Data([2]))
        try await storage.apply(HealthChanges(kind: .steps, replacesKind: true))
        state = try await HistoryStore(directory: directory).snapshot()
        XCTAssertTrue(state.samples.filter { $0.kind == .steps }.isEmpty)
        XCTAssertEqual(state.samples.filter { $0.kind == .sdnn }, [sdnn])
    }
    func testBoundedIncrementalReadExpiresOnlyThatMetricAndPreservesWorkoutsAndHabits() async throws {
        let storage = store()
        let cutoff = date("2026-07-04T10:00:00Z")
        let old = sample(.heartRate, start: cutoff.addingTimeInterval(-1), value: 80)
        let edge = sample(.heartRate, start: cutoff, value: 90)
        let removed = sample(.heartRate, start: cutoff.addingTimeInterval(100), value: 100)
        let workout = sample(.workout, start: cutoff.addingTimeInterval(-86400), value: 30)
        let sdnn = sample(.sdnn, start: workout.start, value: 40)
        let habit = HabitEntry(id: UUID(), kind: .waterML, timestamp: workout.start, value: 200, note: nil, revision: 1, origin: "phone", deleted: false)
        try await storage.apply(HealthChanges(kind: .heartRate, inserted: [old, edge, removed]))
        try await storage.apply(HealthChanges(kind: .workout, inserted: [workout]))
        try await storage.apply(HealthChanges(kind: .sdnn, inserted: [sdnn]))
        try await storage.upsertHabit(habit)
        try await storage.apply(HealthChanges(kind: .heartRate, deletedIDs: [removed.id], newAnchor: Data([3]), retentionStart: cutoff))
        let state = try await storage.snapshot()
        XCTAssertEqual(state.samples.filter { $0.kind == .heartRate }, [edge])
        XCTAssertTrue(state.samples.contains(workout))
        XCTAssertTrue(state.samples.contains(sdnn))
        XCTAssertEqual(state.habits, [habit])
        XCTAssertEqual(state.anchors[.heartRate], Data([3]))
    }
    func testBoundedReadCannotReinsertAnExpiredRecord() async throws {
        let storage = store(), cutoff = date("2026-07-04T10:00:00Z")
        let expired = sample(.heartRate, start: cutoff.addingTimeInterval(-1))
        let current = sample(.heartRate, start: cutoff)
        try await storage.apply(HealthChanges(kind: .heartRate, inserted: [expired, current], retentionStart: cutoff))
        let state = try await storage.snapshot()
        XCTAssertEqual(state.samples, [current])
    }
    func testReplacementHonorsClearEpochBeforeRemovingCurrentData() async throws {
        let storage = store(), current = sample(.steps, start: date("2026-10-02T10:00:00Z"))
        try await storage.apply(HealthChanges(kind: .steps, inserted: [current]))
        let accepted = try await storage.apply(HealthChanges(kind: .steps, replacesKind: true), expectedClearEpoch: UUID())
        XCTAssertFalse(accepted)
        let state = try await storage.snapshot()
        XCTAssertEqual(state.samples, [current])
    }
    func testExpiredWorkoutBoundaryOverlapIsRetainedForExclusion() async throws {
        let storage = store(), cutoff = date("2026-07-04T10:00:00Z")
        let overlapping = HealthSample(id: UUID(), kind: .workout, sourceID: "watch", start: cutoff.addingTimeInterval(-300), end: cutoff.addingTimeInterval(300), value: 10)
        let expired = HealthSample(id: UUID(), kind: .workout, sourceID: "watch", start: cutoff.addingTimeInterval(-1200), end: cutoff.addingTimeInterval(-600), value: 10)
        try await storage.apply(HealthChanges(kind: .workout, inserted: [overlapping, expired]))
        try await storage.apply(HealthChanges(kind: .workout, retentionStart: cutoff))
        let state = try await storage.snapshot()
        XCTAssertEqual(state.samples, [overlapping])
    }
}

#if canImport(HealthKit)
import HealthKit
extension DataReadPolicyTests {
    func testHealthKitDailyStatisticsTypesAreActuallyCumulative() throws {
        for kind in MetricKind.allCases where DataReadPolicy.usesDailyStatistics(kind) {
            let type = try XCTUnwrap(HealthKitRepository.sampleType(kind) as? HKQuantityType)
            XCTAssertEqual(type.aggregationStyle, .cumulative)
        }
    }
}
#endif
final class StatisticsBoundaryTests: XCTestCase {
    func testEarliestStatisticsProbeIncludesTheWholeBoundaryDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let lower = Date(timeIntervalSince1970: 1_759_406_400)
        XCTAssertEqual(DataReadPolicy.statisticsLowerBound(rawLower: lower, calendar: calendar), calendar.startOfDay(for: lower))
        XCTAssertNil(DataReadPolicy.statisticsLowerBound(rawLower: nil, calendar: calendar))
    }
}
