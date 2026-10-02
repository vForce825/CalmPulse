#if DEBUG
import Foundation
import WellnessCore
import WellnessServices
/// Explicitly synthetic fixtures, only reachable with the existing UI-testing launch flag.
enum StressDemonstration {
    static func seed(_ name: String, store: HistoryStore, now: Date = .now) async throws {
        let scores = ["relaxed": 12, "steady": 38, "tense": 62, "high": 88]
        let finalScore = scores[name] ?? 38
        let supported = Set(scores.keys).union(["learning", "stale", "invalid", "unavailable"])
        guard supported.contains(name) else { return }
        try await store.update { state in
            state.settings.requestedMetrics = [.sdnn, .restingHeartRate]
            state.settings.hideWidgetValues = false
            state.samples = []; state.assessments = []
            let ages: [TimeInterval] = name == "stale" ? [18000, 15000, 14400] : [9600, 6600, 4200, 720]
            for (index, age) in ages.enumerated() {
                let observedAt = name == "invalid" ? now.addingTimeInterval(600) : now.addingTimeInterval(-age)
                let value = [46.0, 33.0, 29.0, 42.0][min(index, 3)]
                let sample = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-demonstration", start: observedAt, end: observedAt, value: value, sourceName: "合成演示记录", isAppleWatch: true)
                let score: Int? = ["learning", "unavailable"].contains(name) ? nil : (index == ages.count - 1 ? finalScore : [12, 65, 82, 38][index])
                let assessment = WellnessAssessment(score: score, baselineDayCount: name == "learning" ? 3 : 18, baselineSampleCount: name == "learning" ? 9 : 72, confidence: name == "learning" ? .insufficient : .established, sourceID: sample.sourceID, sampleID: sample.id, observedAt: observedAt)
                state.samples.append(sample); state.assessments.append(assessment)
                state.summary = StoredSummary(assessment: assessment, sdnn: value, sourceDevice: "synthetic", hideValues: false, generatedAt: now)
            }
        }
    }
}
#endif
