import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
final class StorageTests: XCTestCase, @unchecked Sendable {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func sample() -> HealthSample { HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-watch", start: .now, end: .now, value: 20) }
    func testUUIDUpsertDeletionAndAnchorAreAtomic() async throws {
        let url = directory(); let store = HistoryStore(directory: url)
        let s = sample()
        try await store.apply(HealthChanges(kind: .sdnn, inserted: [s,s], newAnchor: Data([1])))
        var state = try await store.snapshot()
        XCTAssertEqual(state.samples.count, 1)
        XCTAssertEqual(state.anchors[.sdnn], Data([1]))
        try await store.apply(HealthChanges(kind: .sdnn, deletedIDs: [s.id], newAnchor: Data([2])))
        state = try await HistoryStore(directory: url).snapshot()
        XCTAssertTrue(state.samples.isEmpty)
        XCTAssertEqual(state.anchors[.sdnn], Data([2]))
    }
    func testLockedStorageThrowsInsteadOfPretendingEmpty() async throws {
        let store = HistoryStore(directory: directory(), isAvailable: { false })
        do { _ = try await store.snapshot(); XCTFail("Locked store must not be an empty successful read") }
        catch { XCTAssertEqual(error as? StorageError, .protectedDataUnavailable) }
    }
    func testTombstoneSurvivesReplayedOldInsertAndEqualRevision() async throws {
        let store = HistoryStore(directory: directory()); let id = UUID()
        func entry(_ revision: UInt64, _ deleted: Bool, _ origin: String = "watch") -> HabitEntry {
            HabitEntry(id: id, kind: .waterML, timestamp: .now, value: deleted ? nil : 250, note: nil, revision: revision, origin: origin, deleted: deleted)
        }
        try await store.upsertHabit(entry(2, true))
        try await store.upsertHabit(entry(1, false))
        try await store.upsertHabit(entry(2, false, "zzzz"))
        let state = try await store.snapshot()
        XCTAssertEqual(state.habits.count, 1)
        XCTAssertEqual(state.habits.first?.deleted, true)
    }
    func testClearIsIdempotentAndCorruptSchemaNotOverwritten() async throws {
        let url = directory(); let store = HistoryStore(directory: url)
        try await store.apply(HealthChanges(kind: .sdnn, inserted: [sample()]))
        try await store.clearLocalData(); try await store.clearLocalData()
        let snapshot = try await store.snapshot(); XCTAssertTrue(snapshot.samples.isEmpty)
        let file = url.appendingPathComponent("history.json")
        try Data("{\"schemaVersion\":99}".utf8).write(to: file)
        do { _ = try await HistoryStore(directory: url).snapshot(); XCTFail("Unknown schema must fail") }
        catch { XCTAssertEqual(error as? StorageError, .unsupportedOrCorruptSchema) }
    }
}
