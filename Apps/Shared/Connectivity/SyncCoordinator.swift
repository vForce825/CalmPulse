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
public extension SyncEnvelope {
    func isEquivalent(to data: Data) -> Bool { (try? JSONDecoder().decode(Self.self, from: data)) == self }
}
public struct MergeResult: Sendable { public var changed: Bool }
public actor SyncCoordinator {
    private let store: HistoryStore
    public init(store: HistoryStore) { self.store = store }
    public func merge(_ envelope: SyncEnvelope) async throws -> MergeResult {
        guard envelope.schemaVersion == 1 else { throw SyncError.unsupportedSchema }
        return try await store.update { state in
            var changed = false
            if envelope.sourceDevice == .iPhone, var settings = envelope.settings,
               settings.revision >= state.settings.revision {
                settings.selectedSourceID = state.settings.selectedSourceID
                settings.requestedMetrics = state.settings.requestedMetrics
                settings.selectedRange = state.settings.selectedRange
                if settings != state.settings {
                    state.settings = settings
                    state.summary?.hideValues = settings.hideWidgetValues; state.peerSummary?.hideValues = settings.hideWidgetValues
                    changed = true
                }
            }
            if var summary = envelope.summary,
               summary.assessment.version == "wellness-sdnn-v1", summary.sdnn.isFinite, summary.sdnn > 0,
               summary.assessment.observedAt.timeIntervalSince1970.isFinite, summary.assessment.observedAt <= Date(),
               summary.generatedAt.timeIntervalSince1970.isFinite, summary.generatedAt <= Date(),
               !state.deletedHealthIDs.contains(summary.assessment.sampleID),
               summary.assessment.score.map({ (0...100).contains($0) }) ?? true {
                let newer = state.peerSummary.map {
                    summary.assessment.observedAt > $0.assessment.observedAt ||
                    (summary.assessment.observedAt == $0.assessment.observedAt && summary.generatedAt > $0.generatedAt)
                } ?? true
                if newer {
                    summary.hideValues = state.settings.hideWidgetValues
                    state.peerSummary = summary; changed = true
                }
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
