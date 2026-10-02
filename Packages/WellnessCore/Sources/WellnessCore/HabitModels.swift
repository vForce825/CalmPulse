import Foundation

public enum HabitKind: String, Codable, CaseIterable, Sendable {
    case mood, waterML, caffeineMG, breathingSeconds
}

public struct HabitEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: HabitKind
    public let timestamp: Date
    public let value: Double?
    public let note: String?
    public let revision: UInt64
    public let origin: String
    public let deleted: Bool

    public init(id: UUID, kind: HabitKind, timestamp: Date, value: Double?, note: String?,
                revision: UInt64, origin: String, deleted: Bool) {
        self.id = id; self.kind = kind; self.timestamp = timestamp; self.value = value
        self.note = note; self.revision = revision; self.origin = origin; self.deleted = deleted
    }
}
