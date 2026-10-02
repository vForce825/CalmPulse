import Foundation
import WellnessCore
public enum SyncError: Error, Equatable { case unsupportedSchema }
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sourceDevice: NotificationOwner
    public var settings: AppSettings?
    public var summary: StoredSummary?
    public var habitChanges: [HabitEntry]
    public init(schemaVersion: Int = 1, sourceDevice: NotificationOwner, settings: AppSettings? = nil, summary: StoredSummary? = nil, habitChanges: [HabitEntry] = []) {
        self.schemaVersion = schemaVersion; self.sourceDevice = sourceDevice; self.settings = settings; self.summary = summary; self.habitChanges = habitChanges
    }
}
public struct MergeResult: Sendable { public var changed: Bool }
public actor SyncCoordinator {
    private let store: HistoryStore
    public init(store: HistoryStore) { self.store = store }
    public func merge(_ envelope: SyncEnvelope) async throws -> MergeResult {
        guard envelope.schemaVersion == 1 else { throw SyncError.unsupportedSchema }
        return try await store.update { state in
            var changed = false
            if envelope.sourceDevice == .iPhone, let settings = envelope.settings,
               settings.revision >= state.settings.revision, settings != state.settings {
                state.settings = settings; changed = true
            }
            if let summary = envelope.summary,
               summary.assessment.version == "wellness-sdnn-v1",
               summary.assessment.observedAt > (state.summary?.assessment.observedAt ?? .distantPast) {
                state.summary = summary; changed = true
            }
            for entry in envelope.habitChanges {
                if let index = state.habits.firstIndex(where: { $0.id == entry.id }) {
                    if HistoryStore.prefers(entry, over: state.habits[index]) { state.habits[index] = entry; changed = true }
                } else { state.habits.append(entry); changed = true }
            }
            return MergeResult(changed: changed)
        }
    }
}
