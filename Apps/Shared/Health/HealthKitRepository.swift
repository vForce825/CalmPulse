#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import WellnessCore

public actor HealthKitRepository: HealthRepository {
    private let healthStore = HKHealthStore()
    private var observers: [MetricKind: HKObserverQuery] = [:]
    public init() {}
    public static var supported: Set<MetricKind> {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        return Set(MetricKind.allCases.filter { sampleType($0) != nil })
    }
    public func requestReadAccess(for kinds: Set<MetricKind>) async throws {
        let read = Set(kinds.compactMap(Self.sampleType))
        guard !read.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: [], read: read)
    }
    public func changes(for kind: MetricKind, anchor data: Data?) async throws -> HealthChanges {
        guard let type = Self.sampleType(kind) else { return HealthChanges(kind: kind) }
        let anchor = try data.flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    let result = HealthChanges(kind: kind,
                        inserted: (samples ?? []).compactMap { SampleNormalizer.normalize($0, kind: kind) },
                        deletedIDs: (deleted ?? []).map(\.uuid),
                        newAnchor: try newAnchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) })
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
            healthStore.execute(query)
        }
    }
    public func observe(_ kinds: Set<MetricKind>, onChange: @escaping @Sendable () async -> Void) async {
        for kind in kinds where observers[kind] == nil {
            guard let type = Self.sampleType(kind) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                let finish = ObserverCompletion(call: completion)
                guard error == nil else { finish.call(); return }
                Task { await onChange(); finish.call() }
            }
            observers[kind] = query
            healthStore.execute(query)
            // System-controlled best effort. Never start a workout to force sampling.
            try? await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
    }
    public static func sampleType(_ kind: MetricKind) -> HKSampleType? {
        switch kind {
        case .sdnn: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate: HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .heartRate: HKObjectType.quantityType(forIdentifier: .heartRate)
        case .steps: HKObjectType.quantityType(forIdentifier: .stepCount)
        case .activeEnergy: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exerciseMinutes: HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .daylightMinutes: HKObjectType.quantityType(forIdentifier: .timeInDaylight)
        case .sleep: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .mindfulnessMinutes: HKObjectType.categoryType(forIdentifier: .mindfulSession)
        case .workout: HKObjectType.workoutType()
        }
    }
}
private struct ObserverCompletion: @unchecked Sendable { let call: () -> Void }
#endif
