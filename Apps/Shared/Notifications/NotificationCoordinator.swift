import Foundation
import WellnessCore
public protocol NotificationClient: Sendable {
    func isAuthorized() async -> Bool
    func schedule(sampleID: UUID) async throws
}
public actor NotificationCoordinator {
    private let store: HistoryStore
    private let client: any NotificationClient
    private let device: NotificationOwner
    public init(store: HistoryStore, client: any NotificationClient, device: NotificationOwner) {
        self.store = store; self.client = client; self.device = device
    }
    public func evaluate(_ assessments: [WellnessAssessment], now: Date = .now, calendar: Calendar = .current) async throws {
        guard await client.isAuthorized() else { return }
        let state = try await store.snapshot()
        var settings = state.settings.notifications; settings.evaluatingDevice = device
        let decision = NotificationPolicy().decision(recent: assessments, settings: settings, lastSentAt: state.lastNotificationAt, now: now, calendar: calendar)
        guard case .send(let sampleID) = decision else { return }
        let reserved = try await store.update { current -> Bool in
            guard !current.deliveredSampleIDs.contains(sampleID),
                  current.lastNotificationAt.map({ now.timeIntervalSince($0) >= 7200 }) ?? true else { return false }
            current.deliveredSampleIDs.insert(sampleID); current.lastNotificationAt = now; return true
        }
        guard reserved else { return }
        do { try await client.schedule(sampleID: sampleID) }
        catch {
            try await store.update { current in
                current.deliveredSampleIDs.remove(sampleID)
                if current.lastNotificationAt == now { current.lastNotificationAt = state.lastNotificationAt }
            }
            throw error
        }
    }
}
