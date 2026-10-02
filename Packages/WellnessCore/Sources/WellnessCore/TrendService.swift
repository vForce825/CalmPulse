import Foundation

public struct TrendPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { sampleID }
    public let sampleID: UUID
    public let sourceID: String
    public let observedAt: Date
    public let value: Double
    public let score: Int?
    public let version: String?
    public init(sampleID: UUID, sourceID: String, observedAt: Date, value: Double, score: Int? = nil, version: String? = nil) {
        self.sampleID = sampleID; self.sourceID = sourceID; self.observedAt = observedAt; self.value = value; self.score = score; self.version = version
    }
}
public struct TrendCoverage: Codable, Equatable, Sendable {
    public let totalCivilDays: Int
    public let coveredCivilDays: Int
    public let sampleCount: Int
    public var fraction: Double { totalCivilDays > 0 ? Double(coveredCivilDays) / Double(totalCivilDays) : 0 }
    public init(totalCivilDays: Int, coveredCivilDays: Int, sampleCount: Int) {
        self.totalCivilDays = totalCivilDays; self.coveredCivilDays = coveredCivilDays; self.sampleCount = sampleCount
    }
}
public struct BandShare: Codable, Equatable, Sendable {
    public let band: WellnessBand
    public let sampleCount: Int
    public let fraction: Double
    public init(band: WellnessBand, sampleCount: Int, fraction: Double) { self.band = band; self.sampleCount = sampleCount; self.fraction = fraction }
}
public struct WeeklyReport: Codable, Equatable, Sendable {
    public let range: DateInterval
    public let sampleCount: Int
    public let coveredCivilDays: Int
    public let medianSDNN: Double?
    public let bandDistribution: [BandShare]
    public let totalCivilDays: Int
    public let habitTotals: [DailyHabitTotal]
    public let sleepMinutes: Double?
    public let steps: Double?
    public let activeEnergyKCAL: Double?
    public let exerciseMinutes: Double?
    public let daylightMinutes: Double?
    public let mindfulnessMinutes: Double?
    public init(range: DateInterval, sampleCount: Int, coveredCivilDays: Int, medianSDNN: Double? = nil, bandDistribution: [BandShare] = [],
                totalCivilDays: Int = 0, habitTotals: [DailyHabitTotal] = [], sleepMinutes: Double? = nil,
                steps: Double? = nil, activeEnergyKCAL: Double? = nil, exerciseMinutes: Double? = nil,
                daylightMinutes: Double? = nil, mindfulnessMinutes: Double? = nil) {
        self.range = range; self.sampleCount = sampleCount; self.coveredCivilDays = coveredCivilDays
        self.medianSDNN = medianSDNN; self.bandDistribution = bandDistribution
        self.totalCivilDays = totalCivilDays; self.habitTotals = habitTotals; self.sleepMinutes = sleepMinutes
        self.steps = steps; self.activeEnergyKCAL = activeEnergyKCAL; self.exerciseMinutes = exerciseMinutes
        self.daylightMinutes = daylightMinutes; self.mindfulnessMinutes = mindfulnessMinutes
    }
}
public struct TrendReport: Codable, Equatable, Sendable {
    public let range: DateInterval
    public let points: [TrendPoint]
    public let coverage: TrendCoverage
    public let bandDistribution: [BandShare]
    public let scoredSampleCount: Int
    public let unscoredSampleCount: Int
    public let sleep: SleepSummary
    public let activities: ActivityReport
    public let habitTotals: [DailyHabitTotal]
    public let habitComparisons: [HabitComparison]
    public let weeklyReports: [WeeklyReport]
    public let sourceID: String?
    public init(range: DateInterval, points: [TrendPoint] = [], coverage: TrendCoverage = TrendCoverage(totalCivilDays: 0, coveredCivilDays: 0, sampleCount: 0),
                bandDistribution: [BandShare] = [], scoredSampleCount: Int = 0, unscoredSampleCount: Int = 0,
                sleep: SleepSummary = SleepSummary(availability: .unavailable), activities: ActivityReport = ActivityReport(availability: .unavailable),
                habitTotals: [DailyHabitTotal] = [], habitComparisons: [HabitComparison] = [], weeklyReports: [WeeklyReport] = [], sourceID: String? = nil) {
        self.range = range; self.points = points; self.coverage = coverage; self.bandDistribution = bandDistribution
        self.scoredSampleCount = scoredSampleCount; self.unscoredSampleCount = unscoredSampleCount
        self.sleep = sleep; self.activities = activities; self.habitTotals = habitTotals; self.habitComparisons = habitComparisons; self.weeklyReports = weeklyReports; self.sourceID = sourceID
    }
}
public struct TrendService: Sendable {
    public init() {}
    public func summarize(samples: [HealthSample], assessments: [WellnessAssessment], habits: [HabitEntry], range: DateInterval, calendar: Calendar) -> TrendReport {
        let candidates = DomainUtilities.uniqueSamples(samples).filter {
            $0.kind == .sdnn && $0.value > 0 && $0.start >= range.start && $0.start < range.end
        }
        let source = DomainUtilities.primarySource(in: candidates)
        let selected = candidates.filter { $0.sourceID == source }
        let selectedByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        var bySample: [UUID: WellnessAssessment] = [:]
        // A nil recalculation takes precedence over a stale scored copy of the same input.
        for assessment in assessments.sorted(by: { ($0.score ?? -1) < ($1.score ?? -1) }) where bySample[assessment.sampleID] == nil {
            guard let sample = selectedByID[assessment.sampleID], assessment.sourceID == sample.sourceID,
                  assessment.observedAt == sample.start, assessment.version == WellnessEngine.version else { continue }
            bySample[assessment.sampleID] = assessment
        }
        let points = selected.map { sample in
            let matching = bySample[sample.id].flatMap { assessment in
                assessment.sourceID == sample.sourceID && assessment.observedAt == sample.start && assessment.version == WellnessEngine.version ? assessment : nil
            }
            let score = matching?.score.flatMap { (0...100).contains($0) ? $0 : nil }
            return TrendPoint(sampleID: sample.id, sourceID: sample.sourceID, observedAt: sample.start, value: sample.value,
                              score: score, version: matching?.version)
        }
        let days = DomainUtilities.civilDays(in: range, calendar: calendar)
        let covered = Set(points.map { calendar.startOfDay(for: $0.observedAt) })
        let coverage = TrendCoverage(totalCivilDays: days.count, coveredCivilDays: covered.count, sampleCount: points.count)
        let sleep = SleepAggregator().summarize(samples: samples, range: range, calendar: calendar)
        let activities = ActivitySummary().summarize(samples: samples, range: range, calendar: calendar)
        let selectedActivitySamples = samples.filter { sample in
            guard let selectedSource = activities.sourceIDs[sample.kind] else { return sample.kind == .heartRate }
            return sample.sourceID == selectedSource
        }
        let insights = HabitInsights()
        let totals = insights.dailyTotals(habits: habits, range: range, calendar: calendar)
        let comparisons = HabitKind.allCases.map {
            insights.compare(kind: $0, samples: selected, habits: habits, range: range, calendar: calendar)
        }
        var weeks: [WeeklyReport] = []
        if range.duration > 0, let first = calendar.dateInterval(of: .weekOfYear, for: range.start) {
            var cursor = first.start
            while cursor < range.end {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: cursor), week.end > cursor else { break }
                let interval = DateInterval(start: max(week.start, range.start), end: min(week.end, range.end))
                let inWeek = points.filter { $0.observedAt >= interval.start && $0.observedAt < interval.end }
                let weekSleep = SleepAggregator().summarize(samples: samples, range: interval, calendar: calendar)
                let weekActivities = ActivitySummary().summarize(samples: selectedActivitySamples, range: interval, calendar: calendar)
                weeks.append(WeeklyReport(range: interval, sampleCount: inWeek.count,
                    coveredCivilDays: Set(inWeek.map { calendar.startOfDay(for: $0.observedAt) }).count,
                    medianSDNN: DomainUtilities.median(inWeek.map(\.value)), bandDistribution: shares(inWeek),
                    totalCivilDays: DomainUtilities.civilDays(in: interval, calendar: calendar).count,
                    habitTotals: insights.dailyTotals(habits: habits, range: interval, calendar: calendar),
                    sleepMinutes: weekSleep.availability == .available ? weekSleep.asleepMinutes : nil,
                    steps: sum(weekActivities.daily.compactMap(\.steps)),
                    activeEnergyKCAL: sum(weekActivities.daily.compactMap(\.activeEnergyKCAL)),
                    exerciseMinutes: sum(weekActivities.daily.compactMap(\.exerciseMinutes)),
                    daylightMinutes: sum(weekActivities.daily.compactMap(\.daylightMinutes)),
                    mindfulnessMinutes: sum(weekActivities.daily.compactMap(\.mindfulnessMinutes))))
                cursor = week.end
            }
        }
        let scored = points.filter { $0.score != nil }.count
        return TrendReport(range: range, points: points, coverage: coverage, bandDistribution: shares(points),
                           scoredSampleCount: scored, unscoredSampleCount: points.count - scored, sleep: sleep,
                           activities: activities, habitTotals: totals, habitComparisons: comparisons, weeklyReports: weeks, sourceID: source)
    }
    private func shares(_ points: [TrendPoint]) -> [BandShare] {
        let bands = points.compactMap { $0.score.flatMap(WellnessBand.init(score:)) }
        return WellnessBand.allCases.map { band in
            let count = bands.filter { $0 == band }.count
            return BandShare(band: band, sampleCount: count, fraction: bands.isEmpty ? 0 : Double(count) / Double(bands.count))
        }
    }
    private func sum(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        return sum.isFinite ? sum : nil
    }

}
