import Foundation
import WellnessCore

/// The phone preserves its complete SDNN and activity history. Watch has a brief local
/// history; raw HR is only a recent cache, with older workout HR read transiently on demand.
public enum DataReadPolicy {
    public static let cacheDays = 90
    public static func statisticsLowerBound(rawLower: Date?, calendar: Calendar) -> Date? { rawLower.map { calendar.startOfDay(for: $0) } }
    public static func retentionStart(for kind: MetricKind, on device: NotificationOwner, now: Date, calendar: Calendar) -> Date? {
        guard device == .watch || kind == .heartRate else { return nil }
        guard let lower = calendar.date(byAdding: .day, value: -cacheDays, to: now) else { return nil }
        // Scoring excludes workouts and the next 30 minutes; retain the boundary lookback.
        return kind == .workout ? lower.addingTimeInterval(-30 * 60) : lower
    }
    public static func samples(_ samples: [HealthSample], within range: DateInterval) -> [HealthSample] {
        guard range.start.timeIntervalSince1970.isFinite, range.end.timeIntervalSince1970.isFinite, range.duration > 0 else { return [] }
        return samples.filter { $0.start >= range.start && $0.start < range.end }
    }
    public static func usesDailyStatistics(_ kind: MetricKind) -> Bool {
        switch kind {
        case .steps, .activeEnergy, .exerciseMinutes, .daylightMinutes: true
        default: false
        }
    }
    /// Synthetic UUIDv8, using two fixed FNV-1a streams over length-delimited keys.
    /// This is a stable cache identity, never a cryptographic/security identifier.
    public static func aggregateID(kind: MetricKind, sourceID: String, dayStart: Date) -> UUID {
        let fields = ["calmpulse-daily-v1", kind.rawValue, sourceID, String(dayStart.timeIntervalSince1970.bitPattern)]
        let key = fields.map { "\($0.utf8.count):\($0)" }.joined()
        func hash(seed: UInt64) -> UInt64 {
            key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        }
        let first = hash(seed: 0xcbf29ce484222325), second = hash(seed: 0x6c62272e07bb0142)
        var bytes = [UInt8]()
        for word in [first, second] {
            for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: word >> shift)) }
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    /// A daily total is a point at the bucket start. Spreading it over 24 hours would
    /// invent an intraday distribution and undercount the unfinished current day.
    public static func dailyAggregate(kind: MetricKind, sourceID: String, sourceName: String?, dayStart: Date, value: Double) -> HealthSample? {
        guard usesDailyStatistics(kind), value.isFinite, value >= 0, dayStart.timeIntervalSince1970.isFinite else { return nil }
        return HealthSample(id: aggregateID(kind: kind, sourceID: sourceID, dayStart: dayStart), kind: kind,
                            sourceID: sourceID, start: dayStart, end: dayStart, value: value, sourceName: sourceName)
    }
}
