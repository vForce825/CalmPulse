#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import WellnessCore

public actor HealthKitRepository: HealthRepository {
    private let healthStore = HKHealthStore()
    private var observers: [MetricKind: HKObserverQuery] = [:]
    public init() {}
    private static var device: NotificationOwner {
        #if os(watchOS)
        .watch
        #else
        .iPhone
        #endif
    }
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
        let now = Date(), calendar = Calendar.current
        let lower = DataReadPolicy.retentionStart(for: kind, on: Self.device, now: now, calendar: calendar)
        if DataReadPolicy.usesDailyStatistics(kind) {
            guard let quantityType = type as? HKQuantityType, quantityType.aggregationStyle == .cumulative else {
                throw HealthReadError.unsupportedStatistics(kind)
            }
            return try await dailyStatistics(for: kind, type: quantityType, lower: DataReadPolicy.statisticsLowerBound(rawLower: lower, calendar: calendar), now: now, calendar: calendar)
        }
        let predicate = lower.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        let anchor = try data.flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    let result = HealthChanges(kind: kind,
                        inserted: (samples ?? []).compactMap { SampleNormalizer.normalize($0, kind: kind) },
                        deletedIDs: (deleted ?? []).map(\.uuid),
                        newAnchor: try newAnchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) },
                        retentionStart: lower)
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
            healthStore.execute(query)
        }
    }
    /// Explicit detail ranges are transient: no cache, anchor, or authorization mutation.
    public func readSamples(for kind: MetricKind, range: DateInterval) async throws -> [HealthSample] {
        guard range.start.timeIntervalSince1970.isFinite, range.end.timeIntervalSince1970.isFinite,
              range.duration > 0, let type = Self.sampleType(kind) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let normalized = DataReadPolicy.samples((samples ?? []).compactMap { SampleNormalizer.normalize($0, kind: kind) }, within: range)
                continuation.resume(returning: normalized)
            }
            healthStore.execute(query)
        }
    }
    private func firstSampleStart(type: HKQuantityType, lower: Date?, now: Date) async throws -> Date? {
        let predicate = HKQuery.predicateForSamples(withStart: lower, end: now, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            // Find only the earliest visible date, never materialize lifetime raw quantities.
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.first?.startDate)
            }
            healthStore.execute(query)
        }
    }
    private func dailyStatistics(for kind: MetricKind, type: HKQuantityType, lower: Date?, now: Date, calendar: Calendar) async throws -> HealthChanges {
        guard let earliest = try await firstSampleStart(type: type, lower: lower, now: now) else {
            return HealthChanges(kind: kind, replacesKind: true)
        }
        // Include complete civil-day buckets at the bounded Watch edge. No phone cutoff.
        let start = calendar.startOfDay(for: max(earliest, lower ?? earliest))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let interval = DateComponents(calendar: calendar, timeZone: calendar.timeZone, day: 1)
        let unit: HKUnit
        switch kind {
        case .steps: unit = .count()
        case .activeEnergy: unit = .kilocalorie()
        default: unit = .minute()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                   options: [.cumulativeSum, .separateBySource],
                                                   anchorDate: start, intervalComponents: interval)
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else { continuation.resume(throwing: HealthReadError.missingStatisticsResults); return }
                var totals: [HealthSample] = []
                collection.enumerateStatistics(from: start, to: now) { statistics, _ in
                    guard statistics.startDate < now else { return }
                    for source in statistics.sources ?? [] {
                        // HKStatistics exposes HKSource, not HKDevice. This source-level
                        // identity is only for cumulative kinds, never an SDNN baseline.
                        guard let quantity = statistics.sumQuantity(for: source),
                              let sample = DataReadPolicy.dailyAggregate(kind: kind,
                                  sourceID: source.bundleIdentifier + "|daily-statistics-source",
                                  sourceName: source.name + " · 每日合计（来源级）",
                                  dayStart: statistics.startDate, value: quantity.doubleValue(for: unit)) else { continue }
                        totals.append(sample)
                    }
                }
                // Refresh every source/day, even on observer wake. Empty days/source
                // deletions must not leave stale totals or obsolete raw UUID records.
                continuation.resume(returning: HealthChanges(kind: kind, inserted: totals, replacesKind: true))
            }
            // With no update handler this query stops after its initial results.
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
