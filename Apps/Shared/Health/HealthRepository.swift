import Foundation
import WellnessCore
public struct HealthChanges: Sendable {
    public var kind: MetricKind
    public var inserted: [HealthSample]
    public var deletedIDs: [UUID]
    public var newAnchor: Data?
    /// A complete per-kind result, including empty results, replaces the old cache atomically.
    public var replacesKind: Bool
    /// Old cached records outside a bounded read window expire on incremental reads too.
    public var retentionStart: Date?
    public init(kind: MetricKind, inserted: [HealthSample] = [], deletedIDs: [UUID] = [], newAnchor: Data? = nil, replacesKind: Bool = false, retentionStart: Date? = nil) {
        self.kind = kind; self.inserted = inserted; self.deletedIDs = deletedIDs; self.newAnchor = newAnchor
        self.replacesKind = replacesKind; self.retentionStart = retentionStart
    }
}
public protocol HealthRepository: Sendable {
    func requestReadAccess(for kinds: Set<MetricKind>) async throws
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges
    /// Transient detail read; does not alter routine cache coverage or anchors.
    func readSamples(for kind: MetricKind, range: DateInterval) async throws -> [HealthSample]
}
public extension HealthRepository {
    /// Existing repositories/mocks can lack historical detail without inventing data.
    func readSamples(for kind: MetricKind, range: DateInterval) async throws -> [HealthSample] { [] }
}
public enum HealthReadError: Error, Equatable {
    case unsupportedStatistics(MetricKind), missingStatisticsResults
}
public enum HealthDataStatus: Equatable, Sendable {
    case empty, available, protected, failed
    public var message: String {
        switch self {
        case .empty: "暂未读到记录"
        case .available: "已读取本机可用记录"
        case .protected: "设备锁定，暂不可读取"
        case .failed: "暂时无法读取，请稍后重试"
        }
    }
}
