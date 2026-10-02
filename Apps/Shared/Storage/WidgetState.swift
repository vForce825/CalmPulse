import Foundation
public struct WidgetState: Sendable {
    public var score: Int?
    public var sdnn: Double?
    public var label: String
    public var observedAt: Date?
    public var nextTransition: Date?
    public let presentation: StressPresentation
    public init(summary: StoredSummary?, now: Date, protectedDataAvailable: Bool) {
        presentation = StressPresentation(summary: summary, now: now,
            status: protectedDataAvailable ? .available : .protected, respectPrivacy: true)
        label = presentation.title
        observedAt = presentation.observedAt
        // Compatibility values stay available to callers, but never bypass the privacy/validity gate.
        guard let summary, let observedAt else { return }
        let age = now.timeIntervalSince(observedAt)
        if age <= StressPresentation.freshnessLimit {
            nextTransition = observedAt.addingTimeInterval(StressPresentation.freshnessLimit + 1)
        }
        score = summary.assessment.score
        sdnn = summary.sdnn
    }
}
public struct WidgetCache: Codable, Sendable {
    public var schemaVersion = 1
    public var summary: StoredSummary?
    public init(summary: StoredSummary?) { self.summary = summary }
}
public enum WidgetCacheFile {
    public static let groupID = "group.com.vforce825.calmpulse"
    public static func read(from file: URL, now: Date) -> WidgetState {
        guard FileManager.default.fileExists(atPath: file.path) else { return WidgetState(summary: nil, now: now, protectedDataAvailable: true) }
        guard let data = try? Data(contentsOf: file), let cache = try? JSONDecoder().decode(WidgetCache.self, from: data), cache.schemaVersion == 1 else {
            return WidgetState(summary: nil, now: now, protectedDataAvailable: false)
        }
        return WidgetState(summary: cache.summary, now: now, protectedDataAvailable: true)
    }
    public static func write(_ summary: StoredSummary?, to file: URL) throws { try ProtectedFile.write(JSONEncoder().encode(WidgetCache(summary: summary)), to: file) }
}
