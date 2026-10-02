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
        guard let latest = assessments.max(by: { $0.observedAt < $1.observedAt }) else { return }
        let claim = try await store.update { current -> NotificationInputClaim? in
            guard current.evaluatedSampleIDs.insert(latest.sampleID).inserted,
                  !current.deletedHealthIDs.contains(latest.sampleID),
                  current.settings.selectedSourceID == nil || current.settings.selectedSourceID == latest.sourceID else { return nil }
            return NotificationInputClaim(generation: current.healthGeneration, clearEpoch: current.clearEpoch, selectedSourceID: current.settings.selectedSourceID)
        }
        guard let claim, await client.isAuthorized() else { return }
        let state = try await store.snapshot()
        guard claim.matches(state) else { return }
        var settings = state.settings.notifications; settings.evaluatingDevice = device
        let decision = NotificationPolicy().decision(recent: assessments, settings: settings, lastSentAt: state.lastNotificationAt, now: now, calendar: calendar)
        guard case .send(let sampleID) = decision else { return }
        let evaluatingDevice = device
        let reserved = try await store.update { current -> Bool in
            guard claim.matches(current), !current.deletedHealthIDs.contains(sampleID) else { return false }
            var currentSettings = current.settings.notifications; currentSettings.evaluatingDevice = evaluatingDevice
            guard NotificationPolicy().decision(recent: assessments, settings: currentSettings, lastSentAt: current.lastNotificationAt, now: now, calendar: calendar).shouldSend else { return false }
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

private struct NotificationInputClaim: Sendable {
    let generation: UUID
    let clearEpoch: UUID
    let selectedSourceID: String?
    func matches(_ state: StoredSnapshot) -> Bool {
        state.healthGeneration == generation && state.clearEpoch == clearEpoch && state.settings.selectedSourceID == selectedSourceID
    }
}
