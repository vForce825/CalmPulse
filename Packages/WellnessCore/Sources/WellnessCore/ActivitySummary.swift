import Foundation

public struct HeartRateZoneConfiguration: Codable, Equatable, Sendable {
    public let boundaries: [Double]
    public init?(boundaries: [Double]) {
        guard !boundaries.isEmpty, boundaries.allSatisfy({ $0.isFinite && $0 > 0 }), zip(boundaries, boundaries.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        self.boundaries = boundaries
    }
}
public struct HeartRateZoneDuration: Codable, Equatable, Sendable {
    public let index: Int
    public let lowerBound: Double?
    public let upperBound: Double?
    public let minutes: Double
    public init(index: Int, lowerBound: Double?, upperBound: Double?, minutes: Double) {
        self.index = index; self.lowerBound = lowerBound; self.upperBound = upperBound; self.minutes = minutes
    }
}
public struct WorkoutSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sourceID: String
    public let start: Date
    public let end: Date
    public let activityType: String?
    public let durationMinutes: Double
    public let heartRateSampleCount: Int
    public let meanHeartRate: Double?
    public let minHeartRate: Double?
    public let maxHeartRate: Double?
    public let zones: [HeartRateZoneDuration]
    public init(id: UUID, sourceID: String, start: Date, end: Date, activityType: String? = nil,
                durationMinutes: Double, heartRateSampleCount: Int = 0, meanHeartRate: Double? = nil,
                minHeartRate: Double? = nil, maxHeartRate: Double? = nil, zones: [HeartRateZoneDuration] = []) {
        self.id = id; self.sourceID = sourceID; self.start = start; self.end = end; self.activityType = activityType
        self.durationMinutes = durationMinutes; self.heartRateSampleCount = heartRateSampleCount; self.meanHeartRate = meanHeartRate
        self.minHeartRate = minHeartRate; self.maxHeartRate = maxHeartRate; self.zones = zones
    }
}
public struct ActivityDaySummary: Codable, Equatable, Sendable {
    public let day: Date
    public let steps: Double?
    public let activeEnergyKCAL: Double?
    public let exerciseMinutes: Double?
    public let daylightMinutes: Double?
    public let mindfulnessMinutes: Double?
    public init(day: Date, steps: Double? = nil, activeEnergyKCAL: Double? = nil, exerciseMinutes: Double? = nil,
                daylightMinutes: Double? = nil, mindfulnessMinutes: Double? = nil) {
        self.day = day; self.steps = steps; self.activeEnergyKCAL = activeEnergyKCAL
        self.exerciseMinutes = exerciseMinutes; self.daylightMinutes = daylightMinutes; self.mindfulnessMinutes = mindfulnessMinutes
    }
}
public struct ActivityReport: Codable, Equatable, Sendable {
    public let availability: DataAvailability
    public let daily: [ActivityDaySummary]
    public let workouts: [WorkoutSummary]
    public let sourceIDs: [MetricKind: String]
    public init(availability: DataAvailability, daily: [ActivityDaySummary] = [], workouts: [WorkoutSummary] = [], sourceIDs: [MetricKind: String] = [:]) {
        self.availability = availability; self.daily = daily; self.workouts = workouts; self.sourceIDs = sourceIDs
    }
}
public struct ActivitySummary: Sendable {
    public init() {}
    public func summarize(samples: [HealthSample], range: DateInterval, calendar: Calendar, zones: HeartRateZoneConfiguration? = nil) -> ActivityReport {
        guard range.duration > 0 else { return ActivityReport(availability: .unavailable) }
        let unique = DomainUtilities.uniqueSamples(samples).filter { sample in
            sample.value >= 0 && (sample.end > sample.start ? sample.end > range.start && sample.start < range.end : sample.start >= range.start && sample.start < range.end)
        }
        let quantityKinds: [MetricKind] = [.steps, .activeEnergy, .exerciseMinutes, .daylightMinutes, .mindfulnessMinutes]
        var sourceIDs: [MetricKind: String] = [:], byDay: [Date: [MetricKind: Double]] = [:]
        for kind in quantityKinds {
            let candidates = unique.filter { $0.kind == kind }
            guard let source = DomainUtilities.primarySource(in: candidates) else { continue }
            sourceIDs[kind] = source
            for sample in candidates where sample.sourceID == source {
                if sample.end == sample.start {
                    byDay[calendar.startOfDay(for: sample.start), default: [:]][kind, default: 0] += sample.value
                } else {
                    for slice in DomainUtilities.slices(start: sample.start, end: sample.end, range: range, calendar: calendar) {
                        let portion = slice.end.timeIntervalSince(slice.start) / sample.end.timeIntervalSince(sample.start)
                        byDay[slice.day, default: [:]][kind, default: 0] += sample.value * portion
                    }
                }
            }
        }
        let daily = byDay.keys.sorted().map { day in
            ActivityDaySummary(day: day, steps: byDay[day]?[.steps], activeEnergyKCAL: byDay[day]?[.activeEnergy],
                               exerciseMinutes: byDay[day]?[.exerciseMinutes], daylightMinutes: byDay[day]?[.daylightMinutes],
                               mindfulnessMinutes: byDay[day]?[.mindfulnessMinutes])
        }
        let workoutCandidates = unique.filter { $0.kind == .workout && $0.end > $0.start }
        let workoutSource = DomainUtilities.primarySource(in: workoutCandidates)
        sourceIDs[.workout] = workoutSource
        let validZones = zones.flatMap { HeartRateZoneConfiguration(boundaries: $0.boundaries) }
        let workouts = workoutCandidates.filter { $0.sourceID == workoutSource }.map { workout in
            let start = max(workout.start, range.start), end = min(workout.end, range.end)
            let heartRates = unique.filter {
                $0.kind == .heartRate && $0.value > 0 && $0.sourceID == workout.sourceID && $0.start >= start && $0.start < end
            }.sorted { $0.start < $1.start }
            var zoneDurations: [Int: Double] = [:]
            if let validZones {
                for (first, second) in zip(heartRates, heartRates.dropFirst()) {
                    let seconds = second.start.timeIntervalSince(first.start)
                    // Never bridge a sparse interval or infer the unmeasured tail of a workout.
                    guard seconds > 0, seconds <= 5 * 60 else { continue }
                    let index = validZones.boundaries.filter { first.value >= $0 }.count
                    zoneDurations[index, default: 0] += seconds / 60
                }
            }
            let zoneSummary = zoneDurations.keys.sorted().map { index in
                HeartRateZoneDuration(index: index, lowerBound: index > 0 ? validZones?.boundaries[index - 1] : nil,
                                      upperBound: index < (validZones?.boundaries.count ?? 0) ? validZones?.boundaries[index] : nil,
                                      minutes: zoneDurations[index]!)
            }
            let values = heartRates.map(\.value)
            return WorkoutSummary(id: workout.id, sourceID: workout.sourceID, start: start, end: end,
                                  activityType: workout.workoutType, durationMinutes: end.timeIntervalSince(start) / 60,
                                  heartRateSampleCount: values.count, meanHeartRate: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                                  minHeartRate: values.min(), maxHeartRate: values.max(), zones: zoneSummary)
        }
        return ActivityReport(availability: daily.isEmpty && workouts.isEmpty ? .unavailable : .available,
                              daily: daily, workouts: workouts, sourceIDs: sourceIDs)
    }
}
