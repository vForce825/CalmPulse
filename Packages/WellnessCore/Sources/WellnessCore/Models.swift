import Foundation

/// Values are normalized to ms, beats/min, count, kcal, or minutes by the platform adapter.
public enum MetricKind: String, Codable, CaseIterable, Sendable {
    case sdnn, restingHeartRate, heartRate, steps, activeEnergy, exerciseMinutes
    case daylightMinutes, sleep, mindfulnessMinutes, workout
}

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, core, deep, rem
    public var isAsleep: Bool { self != .inBed && self != .awake }
}

public struct HealthSample: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: MetricKind
    public let sourceID: String
    public let start: Date
    public let end: Date
    public let value: Double
    public let sleepStage: SleepStage?
    public let sourceName: String?
    public let workoutType: String?
    public let isAppleWatch: Bool

    public init(id: UUID, kind: MetricKind, sourceID: String, start: Date, end: Date, value: Double,
                sleepStage: SleepStage? = nil, sourceName: String? = nil, workoutType: String? = nil, isAppleWatch: Bool = false) {
        self.id = id; self.kind = kind; self.sourceID = sourceID
        self.start = start; self.end = end; self.value = value
        self.sleepStage = sleepStage; self.sourceName = sourceName; self.workoutType = workoutType
        self.isAppleWatch = isAppleWatch
    }
}

public struct WorkoutWindow: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let activityType: String?
    public init(start: Date, end: Date, activityType: String? = nil) {
        self.start = start; self.end = end; self.activityType = activityType
    }
}

public enum WellnessBand: String, Codable, CaseIterable, Sendable {
    case low, moderate, high, highest
    public init?(score: Int) {
        switch score {
        case 0...24: self = .low
        case 25...49: self = .moderate
        case 50...74: self = .high
        case 75...100: self = .highest
        default: return nil
        }
    }
}

public enum BaselineConfidence: String, Codable, Sendable { case insufficient, limited, established }
public enum DataFreshness: String, Codable, Sendable { case fresh, historical }

public struct WellnessAssessment: Codable, Equatable, Sendable {
    public let score: Int?
    public let band: WellnessBand?
    public let baselineDayCount: Int
    public let baselineSampleCount: Int
    public let confidence: BaselineConfidence
    public let version: String
    public let sourceID: String
    public let sampleID: UUID
    public let observedAt: Date
    public let freshness: DataFreshness
    public let baselineRange: DateInterval?

    public init(score: Int?, band: WellnessBand? = nil, baselineDayCount: Int = 0,
                baselineSampleCount: Int = 0, confidence: BaselineConfidence = .insufficient,
                version: String = "wellness-sdnn-v1", sourceID: String, sampleID: UUID,
                observedAt: Date, freshness: DataFreshness = .fresh, baselineRange: DateInterval? = nil) {
        self.score = score; self.band = score.flatMap(WellnessBand.init(score:))
        self.baselineDayCount = baselineDayCount; self.baselineSampleCount = baselineSampleCount
        self.confidence = confidence; self.version = version; self.sourceID = sourceID
        self.sampleID = sampleID; self.observedAt = observedAt; self.freshness = freshness
        self.baselineRange = baselineRange
    }
}

public enum NotificationOwner: String, Codable, CaseIterable, Sendable { case watch, iPhone }

public struct NotificationSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var owner: NotificationOwner
    public var evaluatingDevice: NotificationOwner
    public var quietStartHour: Int
    public var quietEndHour: Int
    public init(enabled: Bool = false, owner: NotificationOwner = .watch,
                evaluatingDevice: NotificationOwner = .watch, quietStartHour: Int = 22,
                quietEndHour: Int = 8) {
        self.enabled = enabled; self.owner = owner; self.evaluatingDevice = evaluatingDevice
        self.quietStartHour = quietStartHour; self.quietEndHour = quietEndHour
    }
}

public enum NotificationSuppression: String, Codable, Sendable {
    case disabled, wrongOwner, quietHours, cooldown, insufficientSamples, stale, alreadySent, invalidSettings
}

public enum NotificationDecision: Equatable, Codable, Sendable {
    case send(sampleID: UUID)
    case suppress(NotificationSuppression)
    public var shouldSend: Bool {
        if case .send = self { return true }
        return false
    }
}
