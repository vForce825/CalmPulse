import Foundation

/// An explicitly defined relative SDNN scale, not a medical or emotional-state estimate.
public struct WellnessEngine: Sendable {
    public static let version = "wellness-sdnn-v1"
    public init() {}

    public func assess(current: HealthSample, history: [HealthSample], workouts: [WorkoutWindow], calendar: Calendar, now: Date) -> WellnessAssessment {
        let freshness: DataFreshness = now.timeIntervalSince(current.start) > 3 * 3600 ? .historical : .fresh
        guard valid(current), now.timeIntervalSince1970.isFinite else {
            return result(current, score: nil, days: 0, samples: 0, freshness: freshness, range: nil)
        }
        let today = calendar.startOfDay(for: current.start)
        guard let firstDay = calendar.date(byAdding: .day, value: -28, to: today) else {
            return result(current, score: nil, days: 0, samples: 0, freshness: freshness, range: nil)
        }
        let range = DateInterval(start: firstDay, end: today)
        var seen = Set<UUID>()
        let baseline = history.filter {
            valid($0) && $0.sourceID == current.sourceID && $0.id != current.id &&
            $0.start >= firstDay && $0.start < today && $0.end <= today && !excluded($0, workouts: workouts)
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.id.uuidString < $1.id.uuidString
        }.filter { seen.insert($0.id).inserted }
        let grouped = Dictionary(grouping: baseline) { calendar.startOfDay(for: $0.start) }
        guard grouped.count >= 7, baseline.count >= 20, current.end <= now, !excluded(current, workouts: workouts) else {
            return result(current, score: nil, days: grouped.count, samples: baseline.count, freshness: freshness, range: range)
        }
        // Each civil day gets one vote, independent of the number of measurements in it.
        let dayPercentiles = grouped.values.map { day -> Double in
            let lower = day.filter { $0.value < current.value }.count
            let tied = day.filter { $0.value == current.value }.count
            return (Double(lower) + Double(tied) / 2) / Double(day.count)
        }
        let percentile = dayPercentiles.reduce(0, +) / Double(dayPercentiles.count)
        let score = min(100, max(0, Int((100 * (1 - percentile)).rounded())))
        return result(current, score: score, days: grouped.count, samples: baseline.count, freshness: freshness, range: range)
    }

    private func valid(_ sample: HealthSample) -> Bool {
        sample.kind == .sdnn && sample.value.isFinite && sample.value > 0 &&
        sample.start.timeIntervalSince1970.isFinite && sample.end.timeIntervalSince1970.isFinite && sample.end >= sample.start
    }
    private func excluded(_ sample: HealthSample, workouts: [WorkoutWindow]) -> Bool {
        workouts.contains { window in
            guard window.start.timeIntervalSince1970.isFinite, window.end.timeIntervalSince1970.isFinite, window.end >= window.start else { return false }
            return sample.start <= window.end.addingTimeInterval(30 * 60) && sample.end >= window.start
        }
    }
    private func result(_ current: HealthSample, score: Int?, days: Int, samples: Int, freshness: DataFreshness, range: DateInterval?) -> WellnessAssessment {
        let confidence: BaselineConfidence = days >= 14 && samples >= 20 ? .established : (days >= 7 && samples >= 20 ? .limited : .insufficient)
        return WellnessAssessment(score: score, baselineDayCount: days, baselineSampleCount: samples, confidence: confidence,
                                  version: Self.version, sourceID: current.sourceID, sampleID: current.id,
                                  observedAt: current.start, freshness: freshness, baselineRange: range)
    }
}
