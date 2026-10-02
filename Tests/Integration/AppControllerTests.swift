import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
private actor EmptyRepository: HealthRepository {
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind) }
}
@MainActor final class AppControllerTests: XCTestCase, @unchecked Sendable {
    func testCreateEditDeleteAndRelaunchPersistHabit() async throws {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = AppController(repository: EmptyRepository(), store: store, supported: Set(MetricKind.allCases), device: .iPhone)
        await model.load()
        await model.saveHabit(kind: .waterML, value: 250, note: "synthetic")
        XCTAssertEqual(model.habits.count, 1)
        guard let original = model.habits.first else { return }
        await model.saveHabit(kind: .waterML, value: 400, note: "edited synthetic", editing: original)
        XCTAssertEqual(model.habits.first?.value, 400)
        let restored = AppController(repository: EmptyRepository(), store: store, supported: [], device: .iPhone)
        await restored.load(); XCTAssertEqual(restored.habits.first?.value, 400)
        if let entry = restored.habits.first { await restored.deleteHabit(entry) }
        await model.load(); XCTAssertTrue(model.habits.isEmpty)
    }
    func testCoreRequestHasNeutralEmptyAndRangeRestores() async throws {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = AppController(repository: EmptyRepository(), store: store, supported: [.sdnn,.restingHeartRate], device: .iPhone)
        await model.request([.sdnn,.restingHeartRate])
        XCTAssertEqual(model.dataStatus, .empty)
        await model.changeSettings { $0.selectedRange = "year" }
        let state = try await store.snapshot(); XCTAssertEqual(state.settings.selectedRange, "year")
    }
    func testInvalidHabitValueNotSaved() async {
        let model = AppController(repository: EmptyRepository(), store: HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), supported: [], device: .iPhone)
        await model.saveHabit(kind: .waterML, value: -.infinity, note: nil)
        XCTAssertTrue(model.habits.isEmpty); XCTAssertNotNil(model.errorMessage)
    }
}

private actor SyntheticRepository: HealthRepository {
    var records: [HealthSample]
    init(records: [HealthSample]) { self.records = records }
    func erase() { records = [] }
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind, inserted: records.filter { $0.kind == kind }, newAnchor: Data([1])) }
}
extension AppControllerTests {
    func testForegroundEmptyReconciliationRemovesCachedHealthSummary() async throws {
        let now = Date(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var records: [HealthSample] = []
        for day in 1...7 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            for value in [10.0,20.0,30.0] { records.append(HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-watch", start: date, end: date, value: value, isAppleWatch: true)) }
        }
        records.append(HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-watch", start: now, end: now, value: 20, isAppleWatch: true))
        let repo = SyntheticRepository(records: records)
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = AppController(repository: repo, store: store, supported: [.sdnn], device: .iPhone, calendar: calendar)
        await model.request([.sdnn]); XCTAssertEqual(model.summary?.assessment.score, 50)
        await repo.erase(); await model.refreshHealth()
        XCTAssertNil(model.summary); XCTAssertTrue(model.samples.isEmpty); XCTAssertEqual(model.dataStatus, .empty)
        let reloaded = try await store.snapshot(); XCTAssertNil(reloaded.summary); XCTAssertTrue(reloaded.samples.isEmpty)
    }
}
extension AppControllerTests {
    func testWatchCanPersistLocalTrendRangeWithoutChangingNotificationAuthority() async throws {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = AppController(repository: EmptyRepository(), store: store, supported: [], device: .watch)
        await model.selectRange("year")
        XCTAssertEqual(model.settings.selectedRange, "year")
        let state = try await store.snapshot(); XCTAssertEqual(state.settings.revision, 0)
        XCTAssertEqual(state.settings.notifications.owner, .watch)
    }
}
