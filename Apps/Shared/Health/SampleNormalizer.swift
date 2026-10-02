#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import WellnessCore
public enum SampleNormalizer {
    public static func normalize(_ sample: HKSample, kind: MetricKind) -> HealthSample? {
        var value: Double
        var stage: SleepStage?
        var workoutType: String?
        if let quantity = sample as? HKQuantitySample {
            let unit: HKUnit
            switch kind {
            case .sdnn: unit = .secondUnit(with: .milli)
            case .heartRate, .restingHeartRate: unit = HKUnit.count().unitDivided(by: .minute())
            case .steps: unit = .count()
            case .activeEnergy: unit = .kilocalorie()
            default: unit = .minute()
            }
            value = quantity.quantity.doubleValue(for: unit)
        } else if let workout = sample as? HKWorkout {
            value = workout.duration / 60
            workoutType = String(workout.workoutActivityType.rawValue)
        } else if let category = sample as? HKCategorySample {
            value = sample.endDate.timeIntervalSince(sample.startDate) / 60
            if kind == .sleep {
                switch HKCategoryValueSleepAnalysis(rawValue: category.value) {
                case .inBed: stage = .inBed
                case .awake: stage = .awake
                case .asleepCore: stage = .core
                case .asleepDeep: stage = .deep
                case .asleepREM: stage = .rem
                default: stage = .asleepUnspecified
                }
            }
        } else { return nil }
        guard value.isFinite, sample.endDate >= sample.startDate else { return nil }
        let source = sample.sourceRevision.source
        let device = sample.device
        let product = sample.sourceRevision.productType ?? "unknown"
        let fallback = [source.name, device?.name ?? "", product].joined(separator: "|")
        let identity = device?.localIdentifier ?? fallback
        let isWatch = product.lowercased().contains("watch") || (device?.model?.lowercased().contains("watch") ?? false)
        let sourceName = source.name + (device?.localIdentifier == nil ? " · 来源身份受系统信息限制" : "")
        return HealthSample(id: sample.uuid, kind: kind, sourceID: source.bundleIdentifier + "|" + identity,
            start: sample.startDate, end: sample.endDate, value: value, sleepStage: stage,
            sourceName: sourceName, workoutType: workoutType, isAppleWatch: isWatch)
    }
}
#endif
