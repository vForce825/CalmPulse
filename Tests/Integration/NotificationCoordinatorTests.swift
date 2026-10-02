import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
private actor NotificationRecorder: NotificationClient {
    var permitted: Bool
    var scheduled: [UUID] = []
    init(permitted: Bool) { self.permitted = permitted }
    func isAuthorized() async -> Bool { permitted }
    func schedule(sampleID: UUID) async throws { scheduled.append(sampleID) }
}
final class NotificationCoordinatorTests: XCTestCase, @unchecked Sendable {
    let now = Date(timeIntervalSince1970: 1_759_406_400) // synthetic fixture, 2025 daytime UTC
    func inputs() -> [WellnessAssessment] { [0.0, -3600.0].map { WellnessAssessment(score: 90, sourceID: "synthetic-watch", sampleID: UUID(), observedAt: now.addingTimeInterval($0)) } }
    func store() async throws -> HistoryStore {
        let store = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try await store.update { $0.settings.notifications = NotificationSettings(enabled: true, owner: .watch, quietStartHour: 0, quietEndHour: 0) }
        return store
    }
    func testSameDecisionScheduledOnceAndPersistsAcrossCoordinator() async throws {
        let store = try await store(); let client = NotificationRecorder(permitted: true); let inputs = inputs()
        let first = NotificationCoordinator(store: store, client: client, device: .watch)
        try await first.evaluate(inputs, now: now)
        try await NotificationCoordinator(store: store, client: client, device: .watch).evaluate(inputs, now: now)
        let scheduled = await client.scheduled; XCTAssertEqual(scheduled.count, 1)
    }
    func testNoAuthorizationAndPhoneCannotScheduleWatchOwnedNotice() async throws {
        let store = try await store(); let denied = NotificationRecorder(permitted: false)
        try await NotificationCoordinator(store: store, client: denied, device: .watch).evaluate(inputs(), now: now)
        let noPermission = await denied.scheduled; XCTAssertTrue(noPermission.isEmpty)
        let allowed = NotificationRecorder(permitted: true)
        try await NotificationCoordinator(store: store, client: allowed, device: .iPhone).evaluate(inputs(), now: now)
        let wrongOwner = await allowed.scheduled; XCTAssertTrue(wrongOwner.isEmpty)
    }
}
