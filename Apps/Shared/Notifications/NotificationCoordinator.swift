import Foundation
import WellnessCore
public protocol NotificationClient: Sendable {
    func isAuthorized() async -> Bool
    func schedule(sampleID: UUID) async throws
    func cancel(sampleID: UUID) async
}
public actor NotificationCoordinator {
    private let store: HistoryStore
    private let client: any NotificationClient
    private let device: NotificationOwner
    public init(store: HistoryStore, client: any NotificationClient, device: NotificationOwner) {
        self.store = store; self.client = client; self.device = device
    }
    public func evaluate(_ assessments: [WellnessAssessment], now: Date = .now, calendar: Calendar = .current) async throws {
        var seen = Set<UUID>()
        let candidates = Array(assessments.filter { $0.observedAt <= now && now.timeIntervalSince($0.observedAt) <= 21_600 }
            .sorted { $0.observedAt == $1.observedAt ? $0.sampleID.uuidString < $1.sampleID.uuidString : $0.observedAt > $1.observedAt }
            .filter { seen.insert($0.sampleID).inserted }.prefix(2))
        guard let latest = candidates.first else { return }
        let claim = try await store.update { current -> NotificationInputClaim? in
            guard candidates.allSatisfy({ current.assessments.contains($0) }),
                  current.evaluatedSampleIDs.insert(latest.sampleID).inserted,
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
            guard claim.matches(current), !current.deletedHealthIDs.contains(sampleID),
                  candidates.allSatisfy({ current.assessments.contains($0) }) else { return false }
            var currentSettings = current.settings.notifications; currentSettings.evaluatingDevice = evaluatingDevice
            guard NotificationPolicy().decision(recent: assessments, settings: currentSettings, lastSentAt: current.lastNotificationAt, now: now, calendar: calendar).shouldSend else { return false }
            guard !current.deliveredSampleIDs.contains(sampleID),
                  current.lastNotificationAt.map({ now.timeIntervalSince($0) >= 7200 }) ?? true else { return false }
            current.deliveredSampleIDs.insert(sampleID); current.lastNotificationAt = now; return true
        }
        guard reserved else { return }
        do {
            try await client.schedule(sampleID: sampleID)
            // UN notification submission is asynchronous and cannot share a transaction
            // with storage. Retract a request invalidated while submission was suspended.
            let completed = try await store.snapshot()
            var completedSettings = completed.settings.notifications
            completedSettings.evaluatingDevice = device
            let stillValid = claim.matches(completed)
                && !completed.deletedHealthIDs.contains(sampleID)
                && candidates.allSatisfy { completed.assessments.contains($0) }
                && NotificationPolicy().decision(recent: candidates, settings: completedSettings,
                    lastSentAt: state.lastNotificationAt, now: now, calendar: calendar).shouldSend
            if !stillValid { await client.cancel(sampleID: sampleID) }
        }
        catch {
            await client.cancel(sampleID: sampleID)
            try await store.update { current in
                guard claim.matches(current) else { return }
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
