import Foundation
#if !os(Linux)
import Observation
#endif
import WellnessCore
#if !os(Linux)
@Observable
#endif
@MainActor public final class AppController {
    public private(set) var samples: [HealthSample] = []
    public private(set) var habits: [HabitEntry] = []
    public private(set) var assessments: [WellnessAssessment] = []
    public private(set) var settings = AppSettings()
    public private(set) var summary: StoredSummary?
    public private(set) var breathing = BreathingSession()
    public private(set) var dataStatus: HealthDataStatus = .empty
    public private(set) var isRefreshing = false
    public var errorMessage: String?
    public var stateDidChange: (@MainActor @Sendable () async -> Void)?
    public let store: HistoryStore
    public let device: NotificationOwner
    private let repository: any HealthRepository
    private let supported: Set<MetricKind>
    private let calendar: Calendar
    public init(repository: any HealthRepository, store: HistoryStore, supported: Set<MetricKind>, device: NotificationOwner, calendar: Calendar = .current) {
        self.repository = repository; self.store = store; self.supported = supported; self.device = device; self.calendar = calendar
    }
    public func load() async {
        do {
            let state = try await store.snapshot()
            samples = state.samples; habits = state.habits.filter { !$0.deleted }.sorted { $0.timestamp > $1.timestamp }
            assessments = state.assessments; settings = state.settings; summary = state.summary; breathing = state.breathing
            dataStatus = samples.isEmpty ? .empty : .available
        } catch { handle(error) }
    }
    public func request(_ kinds: Set<MetricKind>) async {
        do {
            try await PermissionCoordinator(repository: repository, supported: supported).requestFeature(kinds)
            let requested = kinds.intersection(supported)
            try await store.update { $0.settings.requestedMetrics.formUnion(requested) }
            await load(); await refreshHealth()
        } catch { handle(error) }
    }
    public func refreshHealth(full: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        do {
            let state = try await store.snapshot()
            for kind in state.settings.requestedMetrics.intersection(supported) {
                do {
                    let changes = try await repository.changes(for: kind, anchor: full ? nil : state.anchors[kind])
                    // Full foreground reconciliation invalidates data no longer visible through HealthKit.
                    try await store.apply(changes, replacingKind: full)
                } catch {
                    // Preserve other available sections; never describe the failure as read refusal.
                    errorMessage = "部分记录暂时无法读取。可稍后刷新。"
                    if kind == .sdnn { try await store.update { $0.summary = nil; $0.assessments = []; $0.samples.removeAll { $0.kind == .sdnn } } }
                }
            }
            await load(); await recalculate(); await stateDidChange?()
        } catch { handle(error) }
    }
    public func recalculate() async {
        let health = samples
        let preferred = settings.selectedSourceID ?? health.filter { $0.kind == .sdnn && $0.isAppleWatch }.max(by: { $0.start < $1.start })?.sourceID
        let sdnn = health.filter { $0.kind == .sdnn && $0.sourceID == preferred && $0.value.isFinite && $0.value > 0 }.sorted { $0.start < $1.start }
        let workouts = health.filter { $0.kind == .workout }.map { WorkoutWindow(start: $0.start, end: $0.end, activityType: $0.workoutType) }
        let now = Date(); let calendar = self.calendar
        let computed = await Task.detached(priority: .userInitiated) {
            var window: [HealthSample] = []; var result: [WellnessAssessment] = []
            for sample in sdnn {
                let day = calendar.startOfDay(for: sample.start)
                let lower = calendar.date(byAdding: .day, value: -28, to: day) ?? day
                window.removeAll { $0.start < lower }
                result.append(WellnessEngine().assess(current: sample, history: window, workouts: workouts, calendar: calendar, now: now))
                window.append(sample)
            }
            return result
        }.value
        let newSummary: StoredSummary?
        if let last = computed.last, let sample = sdnn.last {
            newSummary = StoredSummary(assessment: last, sdnn: sample.value, sourceDevice: device.rawValue, hideValues: settings.hideWidgetValues,
                generatedAt: summary?.assessment == last && summary?.sdnn == sample.value ? (summary?.generatedAt ?? now) : now)
        } else { newSummary = nil }
        do {
            try await store.update { $0.assessments = computed; $0.summary = newSummary }
            assessments = computed; summary = newSummary
        } catch { handle(error) }
    }
    public func saveHabit(kind: HabitKind, value: Double?, note: String?, editing: HabitEntry? = nil) async {
        guard let value, value.isFinite, value >= 0,
              kind != .mood || (1...5).contains(value),
              (editing?.revision ?? 0) < UInt64.max else { errorMessage = "请输入有效数值"; return }
        let entry = HabitEntry(id: editing?.id ?? UUID(), kind: kind, timestamp: editing?.timestamp ?? .now,
            value: value, note: note.map { String($0.prefix(280)) }, revision: (editing?.revision ?? 0) + 1, origin: device.rawValue, deleted: false)
        do { try await store.upsertHabit(entry); await load(); await stateDidChange?() } catch { handle(error) }
    }
    public func deleteHabit(_ entry: HabitEntry) async {
        guard entry.revision < UInt64.max else { errorMessage = "记录版本已达上限"; return }
        let tombstone = HabitEntry(id: entry.id, kind: entry.kind, timestamp: entry.timestamp, value: nil, note: nil, revision: entry.revision + 1, origin: device.rawValue, deleted: true)
        do { try await store.upsertHabit(tombstone); await load(); await stateDidChange?() } catch { handle(error) }
    }
    public func changeSettings(_ update: @Sendable (inout AppSettings) -> Void) async {
        guard device == .iPhone, settings.revision < UInt64.max else { return }
        do {
            try await store.update { state in
                guard state.settings.revision < UInt64.max else { return }
                update(&state.settings); state.settings.revision += 1
            }
            await load(); await recalculate(); await stateDidChange?()
        } catch { handle(error) }
    }
    public func clearLocalData() async {
        do { try await store.clearLocalData(); await load(); await stateDidChange?() } catch { handle(error) }
    }
    public func updateBreathing(_ action: BreathingAction) async {
        do {
            try await store.update { state in
                switch action {
                case .start(let seconds): state.breathing.start(durationSeconds: seconds)
                case .pause: state.breathing.pause()
                case .resume: state.breathing.resume()
                case .stop: state.breathing.stop()
                }
            }
            await load()
        } catch { handle(error) }
    }
    public func finishBreathingIfNeeded(at date: Date = .now) async {
        guard breathing.durationSeconds > 0, breathing.remaining(at: date) == 0 else { return }
        let origin = device.rawValue
        do {
            try await store.update { state in
                guard state.breathing.durationSeconds > 0, state.breathing.remaining(at: date) == 0 else { return }
                let entry = HabitEntry(id: UUID(), kind: .breathingSeconds, timestamp: date,
                    value: Double(state.breathing.durationSeconds), note: nil, revision: 1, origin: origin, deleted: false)
                state.habits.append(entry); state.breathing.stop()
            }
            await load(); await stateDidChange?()
        } catch { handle(error) }
    }
    private func handle(_ error: Error) {
        errorMessage = error is StorageError ? "受保护数据暂不可读取，解锁后重试" : "操作未完成，请稍后重试"
        if error is StorageError { dataStatus = .protected; samples = []; habits = []; summary = nil; assessments = [] }
    }
}
public enum BreathingAction: Sendable { case start(Int), pause, resume, stop }
