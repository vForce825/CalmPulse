import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices

final class ServicesReviewRepros: XCTestCase, @unchecked Sendable {
    private func store() -> HistoryStore {
        HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    private let now = Date(timeIntervalSince1970: 1_759_406_400)
    private func summary(id: UUID = UUID(), source: String = "watch-A", hidden: Bool = false) -> StoredSummary {
        StoredSummary(assessment: WellnessAssessment(score: 80, sourceID: source, sampleID: id, observedAt: now), sdnn: 12, sourceDevice: "watch", hideValues: hidden)
    }
    func testDeletedHealthSampleMustNotReturnThroughDelayedPeerSummary() async throws {
        let store = store(), sampleID = UUID()
        let value = summary(id: sampleID)
        try await store.update { $0.summary = value }
        try await store.apply(HealthChanges(kind: .sdnn, deletedIDs: [sampleID], newAnchor: Data([1])))
        let deleted = try await store.snapshot()
        XCTAssertNil(deleted.summary)
        _ = try await SyncCoordinator(store: store).merge(SyncEnvelope(sourceDevice: .watch, summary: value))
        let replayed = try await store.snapshot()
        XCTAssertNil(replayed.summary, "A delayed peer message resurrected a known-deleted health reading")
    }
    func testPeerSummaryMustNotOverrideAuthoritativeHiddenSetting() async throws {
        let store = store()
        try await store.update { $0.settings.hideWidgetValues = true }
        _ = try await SyncCoordinator(store: store).merge(SyncEnvelope(sourceDevice: .watch, summary: summary(hidden: false)))
        let state = try await store.snapshot()
        XCTAssertTrue(state.settings.hideWidgetValues)
        let widget = WidgetState(summary: state.summary, now: now, protectedDataAvailable: true)
        XCTAssertNil(widget.sdnn, "A visible peer summary bypassed the local hide-values setting")
        XCTAssertNil(widget.score)
    }
    func testPeerSummaryMustHonorSelectedSource() async throws {
        let store = store()
        try await store.update { $0.settings.selectedSourceID = "watch-B" }
        _ = try await SyncCoordinator(store: store).merge(SyncEnvelope(sourceDevice: .watch, summary: summary(source: "watch-A")))
        let state = try await store.snapshot()
        XCTAssertNil(state.summary, "An unselected source has become the displayed summary")
    }
}

final class SyncEncodingReviewRepros: XCTestCase {
    func testRepeatedEnvelopeEncodingUsedForOfflineDeduplicationIsStable() throws {
        var settings = AppSettings()
        settings.requestedMetrics = Set(MetricKind.allCases)
        let envelope = SyncEnvelope(sourceDevice: .iPhone, settings: settings, habitChanges: [
            HabitEntry(id: UUID(), kind: .waterML, timestamp: Date(timeIntervalSince1970: 0), value: 250, note: "synthetic", revision: 1, origin: "iPhone", deleted: false)
        ])
        let bytes = try (0..<100).map { _ in try JSONEncoder().encode(envelope) }
        XCTAssertTrue(bytes.allSatisfy { envelope.isEquivalent(to: $0) }, "Queue deduplication compares decoded semantic envelopes")
    }
}

final class SourceSelectionReviewRepros: XCTestCase, @unchecked Sendable {
    func testPhoneSettingsMustNotOverwriteWatchLocalSourceIdentifier() async throws {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await store.update { $0.settings.selectedSourceID = "bundle|watch-local-ID" }
        var phone = AppSettings(); phone.revision = 1; phone.selectedSourceID = "bundle|phone-local-ID"
        _ = try await SyncCoordinator(store: store).merge(SyncEnvelope(sourceDevice: .iPhone, settings: phone))
        let state = try await store.snapshot()
        XCTAssertEqual(state.settings.selectedSourceID, "bundle|watch-local-ID", "A phone-local HealthKit identifier is not a portable Watch selection")
    }
}

final class DeviceLocalSettingsTests: XCTestCase, @unchecked Sendable {
    func testPhoneSettingsPreserveWatchPermissionAndRange() async throws {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await store.update { $0.settings.requestedMetrics = [.sdnn,.sleep]; $0.settings.selectedRange = "year" }
        var phone = AppSettings(); phone.revision = 1; phone.requestedMetrics = [.sdnn,.workout]
        let envelope = SyncEnvelope(sourceDevice: .iPhone, settings: phone)
        _ = try await SyncCoordinator(store: store).merge(envelope)
        let state = try await store.snapshot()
        XCTAssertEqual(state.settings.requestedMetrics, [.sdnn,.sleep]); XCTAssertEqual(state.settings.selectedRange, "year")
        let repeatMerge = try await SyncCoordinator(store: store).merge(envelope)
        XCTAssertFalse(repeatMerge.changed)
    }
}
