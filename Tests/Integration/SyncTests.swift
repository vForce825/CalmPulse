import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
final class SyncTests: XCTestCase, @unchecked Sendable {
    func store() -> HistoryStore { HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    func summary(_ date: Date) -> StoredSummary { StoredSummary(assessment: WellnessAssessment(score: 80, sourceID: "synthetic", sampleID: UUID(), observedAt: date), sdnn: 12, sourceDevice: "watch") }
    func testReplayDoesNotChangeAndOlderSummaryCannotReplace() async throws {
        let store = store(); let sync = SyncCoordinator(store: store)
        let fresh = summary(.now)
        let envelope = SyncEnvelope(sourceDevice: .watch, summary: fresh)
        let first = try await sync.merge(envelope); XCTAssertTrue(first.changed)
        let replay = try await sync.merge(envelope); XCTAssertFalse(replay.changed)
        _ = try await sync.merge(SyncEnvelope(sourceDevice: .watch, summary: summary(.distantPast)))
        let state = try await store.snapshot(); XCTAssertEqual(state.summary, fresh)
    }
    func testPhoneSettingsAuthoritativeAndUnknownSchemaRejected() async throws {
        let store = store(); let sync = SyncCoordinator(store: store)
        var phone = AppSettings(); phone.revision = 3; phone.theme = "forest"
        _ = try await sync.merge(SyncEnvelope(sourceDevice: .iPhone, settings: phone))
        var watch = phone; watch.revision = 10; watch.theme = "ocean"
        _ = try await sync.merge(SyncEnvelope(sourceDevice: .watch, settings: watch))
        var state = try await store.snapshot(); XCTAssertEqual(state.settings.theme, "forest")
        do { _ = try await sync.merge(SyncEnvelope(schemaVersion: 99, sourceDevice: .watch)); XCTFail("Unknown schema must reject") }
        catch { XCTAssertEqual(error as? SyncError, .unsupportedSchema) }
        state = try await store.snapshot(); XCTAssertEqual(state.settings.theme, "forest")
    }
    func testEqualRevisionOriginOrderAndTombstone() async throws {
        let store = store(); let sync = SyncCoordinator(store: store); let id = UUID(); let date = Date()
        func item(_ rev: UInt64, _ origin: String, _ deleted: Bool = false) -> HabitEntry {
            HabitEntry(id: id, kind: .mood, timestamp: date, value: 3, note: nil, revision: rev, origin: origin, deleted: deleted)
        }
        _ = try await sync.merge(SyncEnvelope(sourceDevice: .watch, habitChanges: [item(2,"A"),item(2,"B")]))
        var state = try await store.snapshot(); XCTAssertEqual(state.habits.first?.origin, "B")
        _ = try await sync.merge(SyncEnvelope(sourceDevice: .watch, habitChanges: [item(2,"A",true),item(1,"Z")]))
        state = try await store.snapshot(); XCTAssertEqual(state.habits.first?.deleted, true)
    }
}
