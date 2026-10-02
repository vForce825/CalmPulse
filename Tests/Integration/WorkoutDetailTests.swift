import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
private actor HistoricalHeartRateRepository: HealthRepository {
    let readings: [HealthSample]
    var calls = 0
    init(readings: [HealthSample]) { self.readings = readings }
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind) }
    func readSamples(for kind: MetricKind, range: DateInterval) async throws -> [HealthSample] {
        calls += 1
        return readings.filter { $0.kind == kind && range.contains($0.start) }
    }
}
@MainActor final class WorkoutDetailTests: XCTestCase, @unchecked Sendable {
    func testOldWorkoutReadsTransientOptedInHeartRateWithoutCachingLifetimeData() async throws {
        let start = Date().addingTimeInterval(-365 * 86_400), id = UUID()
        let workout = HealthSample(id: id, kind: .workout, sourceID: "synthetic-watch", start: start, end: start.addingTimeInterval(120), value: 2)
        let heart = [0.0,90.0].map { offset in HealthSample(id: UUID(), kind: .heartRate, sourceID: "synthetic-watch", start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset), value: 100 + offset / 3) }
        let repo = HistoricalHeartRateRepository(readings: heart)
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await store.update { $0.samples = [workout]; $0.settings.requestedMetrics = [.workout,.heartRate]; $0.settings.heartRateZoneBoundaries = [110] }
        let model = AppController(repository: repo, store: store, supported: [.heartRate,.workout], device: .iPhone)
        await model.load()
        let raw = WorkoutSummary(id: id, sourceID: workout.sourceID, start: workout.start, end: workout.end, durationMinutes: 2)
        let detailed = try await model.loadWorkoutDetails(raw)
        XCTAssertEqual(detailed?.heartRateSampleCount, 2)
        XCTAssertEqual(detailed?.meanHeartRate, 115)
        let cached = try await store.snapshot(); XCTAssertFalse(cached.samples.contains { $0.kind == .heartRate })
        let calls = await repo.calls; XCTAssertEqual(calls, 1)
    }
    func testNoHeartRateOptInDoesNotQuery() async throws {
        let repo = HistoricalHeartRateRepository(readings: [])
        let model = AppController(repository: repo, store: HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), supported: [.heartRate], device: .iPhone)
        let raw = WorkoutSummary(id: UUID(), sourceID: "synthetic", start: .now, end: Date().addingTimeInterval(60), durationMinutes: 1)
        _ = try await model.loadWorkoutDetails(raw)
        let calls = await repo.calls; XCTAssertEqual(calls, 0)
    }
}
