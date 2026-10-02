import Foundation
import WellnessCore
public struct HealthChanges: Sendable {
    public var kind: MetricKind
    public var inserted: [HealthSample]
    public var deletedIDs: [UUID]
    public var newAnchor: Data?
    public init(kind: MetricKind, inserted: [HealthSample] = [], deletedIDs: [UUID] = [], newAnchor: Data? = nil) {
        self.kind = kind; self.inserted = inserted; self.deletedIDs = deletedIDs; self.newAnchor = newAnchor
    }
}
public protocol HealthRepository: Sendable {
    func requestReadAccess(for kinds: Set<MetricKind>) async throws
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges
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
