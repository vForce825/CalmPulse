import Foundation

public enum DataAvailability: String, Codable, Sendable { case available, unavailable }
public struct SleepStageDuration: Codable, Equatable, Sendable {
    public let stage: SleepStage
    public let minutes: Double
    public init(stage: SleepStage, minutes: Double) { self.stage = stage; self.minutes = minutes }
}
public struct DailySleep: Codable, Equatable, Sendable {
    public let day: Date
    public let asleepMinutes: Double
    public let inBedMinutes: Double
    public let stages: [SleepStageDuration]
    public init(day: Date, asleepMinutes: Double, inBedMinutes: Double, stages: [SleepStageDuration] = []) {
        self.day = day; self.asleepMinutes = asleepMinutes; self.inBedMinutes = inBedMinutes; self.stages = stages
    }
}
public struct SleepSummary: Codable, Equatable, Sendable {
    public let availability: DataAvailability
    public let asleepMinutes: Double
    public let inBedMinutes: Double
    public let stages: [SleepStageDuration]
    public let days: [DailySleep]
    public init(availability: DataAvailability, asleepMinutes: Double = 0, inBedMinutes: Double = 0,
                stages: [SleepStageDuration] = [], days: [DailySleep] = []) {
        self.availability = availability; self.asleepMinutes = asleepMinutes; self.inBedMinutes = inBedMinutes
        self.stages = stages; self.days = days
    }
}
public struct SleepAggregator: Sendable {
    public init() {}
    public func summarize(samples: [HealthSample], range: DateInterval, calendar: Calendar) -> SleepSummary {
        guard range.duration > 0 else { return SleepSummary(availability: .unavailable) }
        let eligible = DomainUtilities.uniqueSamples(samples).filter {
            $0.kind == .sleep && $0.end > $0.start && $0.end > range.start && $0.start < range.end
        }
        guard !eligible.isEmpty else { return SleepSummary(availability: .unavailable) }
        var boundaries = Set<Date>()
        for sample in eligible {
            boundaries.insert(max(sample.start, range.start)); boundaries.insert(min(sample.end, range.end))
        }
        for day in DomainUtilities.civilDays(in: range, calendar: calendar) where day > range.start && day < range.end {
            boundaries.insert(day)
        }
        let ordered = boundaries.sorted()
        var asleepByDay: [Date: Double] = [:], inBedByDay: [Date: Double] = [:]
        var stageByDay: [Date: [SleepStage: Double]] = [:]
        for (start, end) in zip(ordered, ordered.dropFirst()) {
            let covering = eligible.filter { $0.start <= start && $0.end >= end }
            guard !covering.isEmpty else { continue }
            let day = calendar.startOfDay(for: start), minutes = end.timeIntervalSince(start) / 60
            if covering.contains(where: { $0.sleepStage == .inBed }) { inBedByDay[day, default: 0] += minutes }
            // Prefer specific stages over unspecified sleep; resolve source conflicts deterministically.
            let sleeping = covering.filter { ($0.sleepStage ?? .asleepUnspecified).isAsleep }.sorted {
                let a = $0.sleepStage ?? .asleepUnspecified, b = $1.sleepStage ?? .asleepUnspecified
                if (a == .asleepUnspecified) != (b == .asleepUnspecified) { return a != .asleepUnspecified }
                if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
                return a.rawValue < b.rawValue
            }
            if let sleep = sleeping.first {
                let stage = sleep.sleepStage ?? .asleepUnspecified
                asleepByDay[day, default: 0] += minutes
                stageByDay[day, default: [:]][stage, default: 0] += minutes
            }
            if asleepByDay[day] == nil { asleepByDay[day] = 0 }
        }
        let days = Set(asleepByDay.keys).union(inBedByDay.keys).sorted().map { day in
            DailySleep(day: day, asleepMinutes: asleepByDay[day] ?? 0, inBedMinutes: inBedByDay[day] ?? 0,
                       stages: SleepStage.allCases.compactMap { stage in
                stageByDay[day]?[stage].map { SleepStageDuration(stage: stage, minutes: $0) }
            })
        }
        let stages = SleepStage.allCases.compactMap { stage -> SleepStageDuration? in
            let minutes = days.flatMap(\.stages).filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
            return minutes > 0 ? SleepStageDuration(stage: stage, minutes: minutes) : nil
        }
        return SleepSummary(availability: .available, asleepMinutes: days.reduce(0) { $0 + $1.asleepMinutes },
                            inBedMinutes: days.reduce(0) { $0 + $1.inBedMinutes }, stages: stages, days: days)
    }
}
