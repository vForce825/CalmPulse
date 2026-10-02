import Foundation
public struct WidgetState: Sendable {
    public var score: Int?
    public var sdnn: Double?
    public var label: String
    public var observedAt: Date?
    public var nextTransition: Date?
    public init(summary: StoredSummary?, now: Date, protectedDataAvailable: Bool) {
        guard protectedDataAvailable else { label = "解锁后查看"; return }
        guard let summary else { label = "暂未读到记录"; return }
        guard summary.assessment.observedAt <= now, summary.assessment.observedAt.timeIntervalSince1970.isFinite else { label = "时间待校正"; return }
        observedAt = summary.assessment.observedAt
        let age = now.timeIntervalSince(summary.assessment.observedAt)
        label = age > 10_800 ? "历史读数" : "最近读数"
        if age <= 10_800 { nextTransition = summary.assessment.observedAt.addingTimeInterval(10_801) }
        if !summary.hideValues { score = summary.assessment.score; sdnn = summary.sdnn }
        else { label = "已隐藏数值" }
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
