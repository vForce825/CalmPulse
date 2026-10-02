import Foundation
import WellnessCore
public enum StorageError: Error, Equatable { case protectedDataUnavailable, unsupportedOrCorruptSchema }
public struct StoredSnapshot: Codable, Sendable {
    public var schemaVersion = 1
    public var healthGeneration = UUID()
    public var clearEpoch = UUID()
    public var samples: [HealthSample] = []
    public var habits: [HabitEntry] = []
    public var anchors: [MetricKind: Data] = [:]
    public var assessments: [WellnessAssessment] = []
    public var settings = AppSettings()
    public var summary: StoredSummary?
    public var peerSummary: StoredSummary?
    public var deletedHealthIDs: Set<UUID> = []
    public var breathing = BreathingSession()
    public var evaluatedSampleIDs: Set<UUID> = []
    public var deliveredSampleIDs: Set<UUID> = []
    public var lastNotificationAt: Date?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, samples, habits, anchors, assessments, settings, summary, peerSummary, deletedHealthIDs
        case breathing, evaluatedSampleIDs, deliveredSampleIDs, lastNotificationAt, healthGeneration, clearEpoch
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        samples = try c.decode([HealthSample].self, forKey: .samples)
        habits = try c.decode([HabitEntry].self, forKey: .habits)
        anchors = try c.decode([MetricKind: Data].self, forKey: .anchors)
        assessments = try c.decode([WellnessAssessment].self, forKey: .assessments)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        summary = try c.decodeIfPresent(StoredSummary.self, forKey: .summary)
        peerSummary = try c.decodeIfPresent(StoredSummary.self, forKey: .peerSummary)
        deletedHealthIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .deletedHealthIDs) ?? []
        breathing = try c.decode(BreathingSession.self, forKey: .breathing)
        deliveredSampleIDs = try c.decode(Set<UUID>.self, forKey: .deliveredSampleIDs)
        lastNotificationAt = try c.decodeIfPresent(Date.self, forKey: .lastNotificationAt)
        evaluatedSampleIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .evaluatedSampleIDs) ?? deliveredSampleIDs
        healthGeneration = try c.decodeIfPresent(UUID.self, forKey: .healthGeneration) ?? UUID()
        clearEpoch = try c.decodeIfPresent(UUID.self, forKey: .clearEpoch) ?? UUID()
    }
}
public actor HistoryStore {
    private let directory: URL
    private let isAvailable: @Sendable () -> Bool
    private var cached: StoredSnapshot?
    public init(directory: URL, isAvailable: @escaping @Sendable () -> Bool = { true }) {
        self.directory = directory; self.isAvailable = isAvailable
    }
    @discardableResult public func apply(_ changes: HealthChanges, replacingKind: Bool = false, expectedClearEpoch: UUID? = nil) async throws -> Bool {
        var state = try load()
        guard expectedClearEpoch == nil || state.clearEpoch == expectedClearEpoch else { return false }
        state.healthGeneration = UUID()
        if replacingKind { state.samples.removeAll { $0.kind == changes.kind } }
        let deleted = Set(changes.deletedIDs)
        state.deletedHealthIDs.formUnion(deleted)
        if let peer = state.peerSummary, deleted.contains(peer.assessment.sampleID) { state.peerSummary = nil }
        var samples = Dictionary(state.samples.map { ($0.id, $0) }, uniquingKeysWith: { _,new in new })
        for id in deleted { samples.removeValue(forKey: id) }
        for sample in changes.inserted where !deleted.contains(sample.id) { samples[sample.id] = sample }
        state.samples = samples.values.sorted { $0.start < $1.start }
        state.anchors[changes.kind] = changes.newAnchor
        // A deletion can change every percentile baseline, not just the deleted input's score.
        if replacingKind || !changes.deletedIDs.isEmpty { state.assessments = []; state.summary = nil }
        try save(state)
        return true
    }
    public func upsertHabit(_ entry: HabitEntry) async throws {
        var state = try load()
        if let index = state.habits.firstIndex(where: { $0.id == entry.id }) {
            if Self.prefers(entry, over: state.habits[index]) { state.habits[index] = entry }
        } else { state.habits.append(entry) }
        try save(state)
    }
    public static func prefers(_ new: HabitEntry, over old: HabitEntry) -> Bool {
        if new.revision != old.revision { return new.revision > old.revision }
        if new.deleted != old.deleted { return new.deleted }
        return new.origin > old.origin
    }
    public func snapshot() async throws -> StoredSnapshot { try load() }
    @discardableResult public func commitAssessments(_ assessments: [WellnessAssessment], summary: StoredSummary?, expectedGeneration: UUID, selectedSourceID: String?) throws -> Bool {
        var state = try load()
        guard state.healthGeneration == expectedGeneration, state.settings.selectedSourceID == selectedSourceID else { return false }
        state.assessments = assessments; state.summary = summary; try save(state); return true
    }

    public func update<Value: Sendable>(_ mutate: @Sendable (inout StoredSnapshot) -> Value) throws -> Value {
        var state = try load(); let result = mutate(&state); try save(state); return result
    }
    public func clearLocalData() async throws {
        let old = try load()
        var state = StoredSnapshot(); state.settings = old.settings; state.deletedHealthIDs = old.deletedHealthIDs
        state.evaluatedSampleIDs = old.evaluatedSampleIDs
        state.deliveredSampleIDs = old.deliveredSampleIDs; state.lastNotificationAt = old.lastNotificationAt
        // Retain content-free tombstones so an offline watch cannot restore a cleared log.
        state.habits = old.habits.map {
            HabitEntry(id: $0.id, kind: $0.kind, timestamp: $0.timestamp, value: nil, note: nil,
                       revision: $0.deleted ? $0.revision : ($0.revision == UInt64.max ? UInt64.max : $0.revision + 1), origin: $0.origin, deleted: true)
        }
        try save(state)
    }
    private func load() throws -> StoredSnapshot {
        guard isAvailable() else { throw StorageError.protectedDataUnavailable }
        if let cached { return cached }
        let file = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: file.path) else { let state = StoredSnapshot(); cached = state; return state }
        let data = try Data(contentsOf: file)
        guard let state = try? JSONDecoder().decode(StoredSnapshot.self, from: data), state.schemaVersion == 1 else {
            throw StorageError.unsupportedOrCorruptSchema
        }
        cached = state; return state
    }
    private func save(_ incoming: StoredSnapshot) throws {
        var state = incoming
        state.summary?.hideValues = state.settings.hideWidgetValues
        state.peerSummary?.hideValues = state.settings.hideWidgetValues
        guard isAvailable() else { throw StorageError.protectedDataUnavailable }
        try ProtectedFile.write(JSONEncoder().encode(state), to: directory.appendingPathComponent("history.json"))
        cached = state
    }
}
