import Foundation
import XCTest
import WellnessCore
@testable import WellnessServices
private actor ReadRecorder: HealthRepository {
    var requested: Set<MetricKind> = []
    func requestReadAccess(for kinds: Set<MetricKind>) async throws { requested.formUnion(kinds) }
    func changes(for kind: MetricKind, anchor: Data?) async throws -> HealthChanges { HealthChanges(kind: kind) }
}
final class PermissionTests: XCTestCase, @unchecked Sendable {
    func testCoreFirstAndOptionalAvailabilityFiltering() async throws {
        let recorder = ReadRecorder()
        let coordinator = PermissionCoordinator(repository: recorder, supported: [.sdnn,.restingHeartRate,.sleep])
        try await coordinator.requestCore()
        var requested = await recorder.requested
        XCTAssertEqual(requested, [.sdnn,.restingHeartRate])
        try await coordinator.requestFeature([.sleep,.daylightMinutes])
        requested = await recorder.requested
        XCTAssertEqual(requested, [.sdnn,.restingHeartRate,.sleep])
    }
    func testEmptyOptionalDataDoesNotBlockCore() async throws {
        let recorder = ReadRecorder()
        let changes = try await recorder.changes(for: .sleep, anchor: nil)
        XCTAssertTrue(changes.inserted.isEmpty)
        try await PermissionCoordinator(repository: recorder, supported: [.sdnn]).requestCore()
        let requested = await recorder.requested; XCTAssertEqual(requested, [.sdnn])
    }
}
