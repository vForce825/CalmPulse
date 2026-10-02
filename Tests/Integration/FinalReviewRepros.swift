import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices

private actor FinalReviewEmptyRepository: HealthRepository {
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind) }
}

@MainActor final class FinalReviewRepros: XCTestCase, @unchecked Sendable {
    private func store() -> HistoryStore { HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    private func model(_ store: HistoryStore, device: NotificationOwner = .iPhone) -> AppController {
        AppController(repository: FinalReviewEmptyRepository(), store: store, supported: Set(MetricKind.allCases), device: device)
    }
    func testPhoneSettingsDoNotEraseWatchLocalRequestedMetrics() async throws {
        let store = store()
        try await store.update { $0.settings.requestedMetrics = [.sdnn, .sleep] }
        var phone = AppSettings(); phone.revision = 1; phone.requestedMetrics = [.sdnn]
        _ = try await SyncCoordinator(store: store).merge(SyncEnvelope(sourceDevice: .iPhone, settings: phone))
        let state = try await store.snapshot()
        XCTAssertTrue(state.settings.requestedMetrics.contains(.sleep), "A theme/settings sync erases the Watch sleep opt-in and stops further sleep queries")
    }
    func testWatchTrendRangeCanBeChangedByItsDisplayedPicker() async throws {
        let store = store()
        let model = model(store, device: .watch)
        await model.load()
        await model.selectRange("year")
        XCTAssertEqual(model.settings.selectedRange, "year", "Watch TrendsView invokes this setter but it unconditionally rejects Watch")
    }
    func testNilDeviceIdentityDoesNotDiscardNonBaselineActivity() async throws {
        let now = Date()
        let a = UUID(), b = UUID()
        let first = HealthSample(id: a, kind: .steps, sourceID: SourceIdentity.key(for: .steps, bundle: "synthetic-app", localDeviceID: nil, sampleID: a), start: now, end: now, value: 100)
        let second = HealthSample(id: b, kind: .steps, sourceID: SourceIdentity.key(for: .steps, bundle: "synthetic-app", localDeviceID: nil, sampleID: b), start: now.addingTimeInterval(60), end: now.addingTimeInterval(60), value: 200)
        let report = ActivitySummary().summarize(samples: [first, second], range: DateInterval(start: now, duration: 3600), calendar: .current)
        XCTAssertEqual(report.daily.compactMap(\.steps).reduce(0, +), 300, "One synthetic source with missing device IDs is reduced to one sample")
    }
    func testClearDuringRecalculationCannotResurrectSummary() async throws {
        let store = store(), now = Date()
        let records = (0..<4500).map { index in
            let date = now.addingTimeInterval(Double(-4500 + index) * 600)
            return HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-watch", start: date, end: date, value: Double(10 + index % 20), isAppleWatch: true)
        }
        try await store.update { $0.samples = records }
        let model = model(store); await model.load()
        let recalculation = Task { await model.recalculate() }
        // Allow the main actor to capture the data and suspend on detached calculation.
        try await Task.sleep(for: .milliseconds(25))
        await model.clearLocalData()
        XCTAssertNil(model.summary)
        await recalculation.value
        let cleared = try await store.snapshot()
        XCTAssertTrue(cleared.samples.isEmpty)
        XCTAssertNil(cleared.summary, "Recalculation rewrote deleted summary after clear returned successfully")
        XCTAssertTrue(cleared.assessments.isEmpty, "Recalculation rewrote deleted assessment history")
    }
}

private actor FinalReviewNotificationRecorder: NotificationClient {
    var scheduled: [UUID] = []
    func isAuthorized() async -> Bool { true }
    func schedule(sampleID: UUID) async throws { scheduled.append(sampleID) }
}

private actor FinalReviewGatedRepository: HealthRepository {
    var records: [HealthSample]
    var continuation: CheckedContinuation<Void, Never>?
    var began = false
    init(records: [HealthSample]) { self.records = records }
    func requestReadAccess(for kinds: Set<MetricKind>) async throws {}
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges {
        let captured = records
        if !began {
            began = true
            await withCheckedContinuation { continuation = $0 }
        }
        return HealthChanges(kind: kind, inserted: captured)
    }
    func beganQuery() -> Bool { began }
    func insert(_ sample: HealthSample) { records.append(sample) }
    func release() { continuation?.resume(); continuation = nil }
}

extension FinalReviewRepros {
    func testClearPreservesNotificationCooldownForTheSameReading() async throws {
        let store = store(), now = Date(), client = FinalReviewNotificationRecorder()
        let input = [now.addingTimeInterval(-60), now.addingTimeInterval(-3600)].map {
            WellnessAssessment(score: 90, sourceID: "synthetic-watch", sampleID: UUID(), observedAt: $0)
        }
        try await store.update { $0.settings.notifications = NotificationSettings(enabled: true, owner: .watch, quietStartHour: 0, quietEndHour: 0) }
        let coordinator = NotificationCoordinator(store: store, client: client, device: .watch)
        try await coordinator.evaluate(input, now: now)
        try await store.clearLocalData()
        try await coordinator.evaluate(input, now: now.addingTimeInterval(60))
        let sent = await client.scheduled
        XCTAssertEqual(sent.count, 1, "Clearing cache lets identical reading notify again after one minute")
    }
    func testObserverEventDuringRefreshMustNotBeDiscarded() async throws {
        let now = Date(), store = store()
        let a = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic", start: now, end: now, value: 20, isAppleWatch: true)
        let b = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic", start: now.addingTimeInterval(-1), end: now.addingTimeInterval(-1), value: 30, isAppleWatch: true)
        let repo = FinalReviewGatedRepository(records: [a])
        try await store.update { $0.settings.requestedMetrics = [.sdnn] }
        let model = AppController(repository: repo, store: store, supported: [.sdnn], device: .iPhone)
        let first = Task { await model.refreshHealth(full: false) }
        while !(await repo.beganQuery()) { await Task.yield() }
        await repo.insert(b)
        // This is the same call made by the HealthKit observer closure.
        await model.refreshHealth(full: false)
        await repo.release()
        await first.value
        XCTAssertTrue(model.samples.contains { $0.id == b.id }, "The observer call returned successfully without draining the new reading")
    }
}

extension FinalReviewRepros {
    func testQuietHoursInputDoesNotBecomeEligibleOnUnrelatedLocalMutation() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9, minute: 55))!
        let store = store(), client = FinalReviewNotificationRecorder()
        let input = [now.addingTimeInterval(-60), now.addingTimeInterval(-3600)].map {
            WellnessAssessment(score: 90, sourceID: "synthetic-watch", sampleID: UUID(), observedAt: $0)
        }
        try await store.update { $0.settings.notifications = NotificationSettings(enabled: true, owner: .watch, quietStartHour: 22, quietEndHour: 10) }
        let coordinator = NotificationCoordinator(store: store, client: client, device: .watch)
        try await coordinator.evaluate(input, now: now, calendar: calendar)
        try await store.update { $0.settings.theme = "forest" }
        // Mirrors publishChanges after changing the theme, with no new input.
        try await coordinator.evaluate(input, now: now.addingTimeInterval(360), calendar: calendar)
        let sent = await client.scheduled
        XCTAssertTrue(sent.isEmpty, "An already-consumed input triggers merely because settings changed")
    }
}

private actor ReReviewPausedNotificationClient: NotificationClient {
    var entered = false
    var gate: CheckedContinuation<Bool, Never>?
    var sent: [UUID] = []
    func isAuthorized() async -> Bool {
        entered = true
        return await withCheckedContinuation { gate = $0 }
    }
    func schedule(sampleID: UUID) async throws { sent.append(sampleID) }
    func hasEntered() -> Bool { entered }
    func release() { gate?.resume(returning: true); gate = nil }
}

extension FinalReviewRepros {
    func testDeletedInputDuringNotificationPermissionLookupCannotSchedule() async throws {
        let store = store(), now = Date(), client = ReReviewPausedNotificationClient()
        let input = [now.addingTimeInterval(-60), now.addingTimeInterval(-3600)].map {
            WellnessAssessment(score: 90, sourceID: "synthetic-watch", sampleID: UUID(), observedAt: $0)
        }
        try await store.update {
            $0.settings.notifications = NotificationSettings(enabled: true, owner: .watch, quietStartHour: 0, quietEndHour: 0)
            $0.assessments = input
        }
        let coordinator = NotificationCoordinator(store: store, client: client, device: .watch)
        let evaluation = Task { try await coordinator.evaluate(input, now: now) }
        while !(await client.hasEntered()) { await Task.yield() }
        try await store.apply(HealthChanges(kind: .sdnn, deletedIDs: [input[0].sampleID]))
        await client.release()
        try await evaluation.value
        let sent = await client.sent
        XCTAssertTrue(sent.isEmpty, "A deleted input still generated a notification after asynchronous authorization lookup")
    }
}

extension FinalReviewRepros {
    func testExistingSchemaOneStoreSurvivesAddedGenerationFields() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var original = StoredSnapshot()
        original.habits = [HabitEntry(id: UUID(), kind: .waterML, timestamp: .now, value: 250, note: "synthetic", revision: 1, origin: "watch", deleted: false)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        // These keys did not exist in the preceding schemaVersion == 1 build.
        object.removeValue(forKey: "healthGeneration")
        object.removeValue(forKey: "clearEpoch")
        object.removeValue(forKey: "evaluatedSampleIDs")
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("history.json"))
        let restored = try await HistoryStore(directory: directory).snapshot()
        XCTAssertEqual(restored.habits.first?.value, 250)
    }
}
extension FinalReviewRepros {
    func testClearDuringNotificationPermissionLookupCannotSchedule() async throws {
        let store = store(), now = Date(), client = ReReviewPausedNotificationClient()
        let input = [now, now.addingTimeInterval(-3600)].map { WellnessAssessment(score: 90, sourceID: "synthetic", sampleID: UUID(), observedAt: $0) }
        try await store.update { $0.settings.notifications = NotificationSettings(enabled: true, owner: .watch, quietStartHour: 0, quietEndHour: 0) }
        let coordinator = NotificationCoordinator(store: store, client: client, device: .watch)
        let evaluation = Task { try await coordinator.evaluate(input, now: now) }
        while !(await client.hasEntered()) { await Task.yield() }
        try await store.clearLocalData(); await client.release(); try await evaluation.value
        let sent = await client.sent; XCTAssertTrue(sent.isEmpty)
    }
    func testClearWinsOverAnInFlightHealthQuery() async throws {
        let now = Date(), store = store()
        let sample = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic", start: now, end: now, value: 20, isAppleWatch: true)
        let repo = FinalReviewGatedRepository(records: [sample])
        try await store.update { $0.settings.requestedMetrics = [.sdnn] }
        let model = AppController(repository: repo, store: store, supported: [.sdnn], device: .iPhone)
        let refresh = Task { await model.refreshHealth() }
        while !(await repo.beganQuery()) { await Task.yield() }
        await model.clearLocalData(); await repo.release(); await refresh.value
        let state = try await store.snapshot(); XCTAssertTrue(state.samples.isEmpty); XCTAssertNil(state.summary)
    }
}
