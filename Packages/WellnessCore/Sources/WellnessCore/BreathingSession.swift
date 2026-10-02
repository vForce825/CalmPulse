import Foundation
/// Persist this value after each action. Display refreshes never drive elapsed time.
public struct BreathingSession: Codable, Equatable, Sendable {
    public private(set) var durationSeconds: Int = 0
    public private(set) var startedAt: Date?
    public private(set) var pausedRemaining: Int?
    public var isPaused: Bool { pausedRemaining != nil }
    public init() {}
    public mutating func start(durationSeconds: Int, at date: Date = .now) {
        self.durationSeconds = min(3600, max(0, durationSeconds))
        startedAt = date
        pausedRemaining = nil
    }
    public mutating func pause(at date: Date = .now) {
        guard startedAt != nil, !isPaused else { return }
        pausedRemaining = remaining(at: date)
    }
    public mutating func resume(at date: Date = .now) {
        guard let remainder = pausedRemaining else { return }
        startedAt = date.addingTimeInterval(-Double(durationSeconds - remainder))
        pausedRemaining = nil
    }
    public mutating func stop() { durationSeconds = 0; startedAt = nil; pausedRemaining = nil }
    public func remaining(at date: Date) -> Int {
        if let pausedRemaining { return pausedRemaining }
        guard let startedAt else { return 0 }
        return max(0, durationSeconds - Int(max(0, date.timeIntervalSince(startedAt)).rounded(.down)))
    }
}
