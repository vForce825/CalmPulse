import Foundation

/// This policy only qualifies new readings; platform scheduling and delivery are never guaranteed.
public struct NotificationPolicy: Sendable {
    public init() {}
    public func decision(recent: [WellnessAssessment], settings: NotificationSettings, lastSentAt: Date?, now: Date, calendar: Calendar) -> NotificationDecision {
        guard settings.enabled else { return .suppress(.disabled) }
        guard settings.owner == settings.evaluatingDevice else { return .suppress(.wrongOwner) }
        guard (0...23).contains(settings.quietStartHour), (0...23).contains(settings.quietEndHour), now.timeIntervalSince1970.isFinite else {
            return .suppress(.invalidSettings)
        }
        if let lastSentAt, !lastSentAt.timeIntervalSince1970.isFinite { return .suppress(.invalidSettings) }
        let hour = calendar.component(.hour, from: now)
        let start = settings.quietStartHour, end = settings.quietEndHour
        let quiet = start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
        guard !quiet else { return .suppress(.quietHours) }
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < 2 * 3600 { return .suppress(.cooldown) }
        var seen = Set<UUID>()
        let chronological = recent.filter {
            $0.observedAt.timeIntervalSince1970.isFinite && $0.observedAt <= now && now.timeIntervalSince($0.observedAt) <= 6 * 3600
        }.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
            return $0.sampleID.uuidString < $1.sampleID.uuidString
        }.filter { seen.insert($0.sampleID).inserted }
        guard let latest = chronological.first else { return .suppress(.insufficientSamples) }
        guard now.timeIntervalSince(latest.observedAt) <= 3 * 3600, latest.freshness == .fresh else { return .suppress(.stale) }
        if let lastSentAt, latest.observedAt <= lastSentAt { return .suppress(.alreadySent) }
        // The newest two readings must both qualify, and a source/algorithm change cannot borrow the older baseline.
        guard chronological.count >= 2 else { return .suppress(.insufficientSamples) }
        let previous = chronological[1]
        guard latest.band == .highest, previous.band == .highest,
              latest.score.map({ (75...100).contains($0) }) == true,
              previous.score.map({ (75...100).contains($0) }) == true,
              latest.sourceID == previous.sourceID, !latest.sourceID.isEmpty,
              latest.version == WellnessEngine.version, previous.version == latest.version else {
            return .suppress(.insufficientSamples)
        }
        return .send(sampleID: latest.sampleID)
    }
}
