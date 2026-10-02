import WellnessCore
/// HealthKit deliberately does not reveal whether read access was refused.
public struct PermissionCoordinator: Sendable {
    private let repository: any HealthRepository
    private let supported: Set<MetricKind>
    public init(repository: any HealthRepository, supported: Set<MetricKind>) { self.repository = repository; self.supported = supported }
    public func requestCore() async throws { try await requestFeature([.sdnn, .restingHeartRate]) }
    public func requestFeature(_ kinds: Set<MetricKind>) async throws {
        let available = kinds.intersection(supported)
        guard !available.isEmpty else { return }
        try await repository.requestReadAccess(for: available)
    }
}
