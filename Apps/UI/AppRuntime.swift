import Foundation
import SwiftUI
import WidgetKit
import WellnessCore
import WellnessServices
@MainActor final class AppRuntime {
    let model: AppController
    private let repository: any HealthRepository
    private let store: HistoryStore
    private let notification: NotificationCoordinator
    private var bridge: WatchBridge?
    private var lastQueued: SyncEnvelope?
    private var started = false
    let testing: Bool
    #if os(watchOS)
    static let device = NotificationOwner.watch
    #else
    static let device = NotificationOwner.iPhone
    #endif
    init() {
        #if DEBUG
        testing = ProcessInfo.processInfo.environment["CALMPULSE_UI_TESTING"] == "1"
        #else
        testing = false
        #endif
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let namespace = UUID(uuidString: ProcessInfo.processInfo.environment["CALMPULSE_UI_TEST_NAMESPACE"] ?? "")?.uuidString ?? "default"
        let directory = root.appendingPathComponent(testing ? "CalmPulse-Demonstration-Tests-" + namespace : "CalmPulse")
        store = HistoryStore(directory: directory)
        repository = testing ? DemonstrationEmptyRepository() : HealthKitRepository()
        model = AppController(repository: repository, store: store, supported: testing ? Set(MetricKind.allCases) : HealthKitRepository.supported, device: Self.device)
        notification = NotificationCoordinator(store: store, client: SystemNotificationClient(), device: Self.device)
        model.stateDidChange = { [weak self] in await self?.publishChanges() }
    }
    var watchInstalled: Bool { bridge?.watchInstalled ?? false }
    func start() async {
        guard !started else { return }; started = true
        await model.load()
        if !testing {
            let sync = SyncCoordinator(store: store)
            bridge = WatchBridge(receive: { [weak self] envelope in
                guard let self else { return }
                do { _ = try await sync.merge(envelope); await self.model.load(); await self.writeWidget() }
                catch { await MainActor.run { self.model.errorMessage = "同步暂未完成，下次打开时会重试" } }
            }, ready: { [weak self] in await self?.publishChanges() })
            bridge?.start()
            await observe(); await model.refreshHealth()
        }
    }
    func foreground() async { await start(); if !testing { await model.refreshHealth() } }
    func observe() async {
        guard !testing, let repository = repository as? HealthKitRepository else { return }
        await repository.observe(model.settings.requestedMetrics) { [weak model] in await model?.refreshHealth(full: false) }
    }
    func enableNotifications(_ enabled: Bool) async {
        if enabled {
            do {
                guard try await SystemNotificationClient().requestPermission() else { model.errorMessage = "系统通知未启用。可在系统设置中调整。"; return }
            } catch { model.errorMessage = "暂时无法启用通知"; return }
        }
        await model.changeSettings { $0.notifications.enabled = enabled }
    }
    private func publishChanges() async {
        await writeWidget(); await observe()
        guard !testing else { return }
        do {
            let state = try await store.snapshot()
            try await notification.evaluate(state.assessments)
            let habits = state.habits.sorted { $0.id.uuidString < $1.id.uuidString }
            let all = SyncEnvelope(sourceDevice: Self.device, settings: Self.device == .iPhone ? state.settings : nil,
                                   summary: state.summary, habitChanges: habits)
            guard all != lastQueued else { return }
            var success = true
            let chunks = max(1, (habits.count + 39) / 40)
            for index in 0..<chunks {
                let start = min(index * 40, habits.count), end = min((index + 1) * 40, habits.count)
                let envelope = SyncEnvelope(sourceDevice: Self.device, settings: all.settings, summary: all.summary, habitChanges: Array(habits[start..<end]))
                success = (bridge?.queue(envelope) ?? false) && success
            }
            if success { lastQueued = all }
        } catch { model.errorMessage = "本机数据暂不可用，已暂停提醒和同步" }
    }
    private func writeWidget() async {
        guard !testing, let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetCacheFile.groupID) else { return }
        let file = group.appendingPathComponent("summary.json")
        do {
            let cache = WidgetCache(summary: model.summary)
            let data = try JSONEncoder().encode(cache)
            guard (try? Data(contentsOf: file)) != data else { return }
            try ProtectedFile.write(data, to: file)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { model.errorMessage = "小组件将在受保护数据可用后更新" }
    }
}
private actor DemonstrationEmptyRepository: HealthRepository {
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind) }
}
