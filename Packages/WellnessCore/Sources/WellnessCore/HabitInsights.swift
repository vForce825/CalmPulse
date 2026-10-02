import Foundation

public struct DailyHabitTotal: Codable, Equatable, Sendable {
    public let day: Date
    public let kind: HabitKind
    public let total: Double
    public let entryCount: Int
    public init(day: Date, kind: HabitKind, total: Double, entryCount: Int) {
        self.day = day; self.kind = kind; self.total = total; self.entryCount = entryCount
    }
}
public enum HabitComparisonStatus: String, Codable, Sendable { case association, informationInsufficient }
public enum HabitAssociationDirection: String, Codable, Sendable { case higherSDNN, lowerSDNN, noDifference }
public struct HabitComparison: Codable, Equatable, Sendable {
    public let kind: HabitKind
    public let status: HabitComparisonStatus
    public let pairedDayCount: Int
    public let lowGroupCount: Int
    public let highGroupCount: Int
    public let lowMedianSDNN: Double?
    public let highMedianSDNN: Double?
    public let difference: Double?
    public let direction: HabitAssociationDirection?
    public let sourceID: String?
    public let caveat: String
    public init(kind: HabitKind, status: HabitComparisonStatus, pairedDayCount: Int = 0,
                lowGroupCount: Int = 0, highGroupCount: Int = 0, lowMedianSDNN: Double? = nil,
                highMedianSDNN: Double? = nil, difference: Double? = nil, direction: HabitAssociationDirection? = nil,
                sourceID: String? = nil, caveat: String = "相关不代表因果") {
        self.kind = kind; self.status = status; self.pairedDayCount = pairedDayCount
        self.lowGroupCount = lowGroupCount; self.highGroupCount = highGroupCount
        self.lowMedianSDNN = lowMedianSDNN; self.highMedianSDNN = highMedianSDNN
        self.difference = difference; self.direction = direction; self.sourceID = sourceID; self.caveat = caveat
    }
}
public struct HabitInsights: Sendable {
    public init() {}
    public func dailyTotals(habits: [HabitEntry], range: DateInterval, calendar: Calendar) -> [DailyHabitTotal] {
        guard range.duration > 0 else { return [] }
        let valid = DomainUtilities.canonicalHabits(habits).filter {
            !$0.deleted && $0.timestamp.timeIntervalSince1970.isFinite && $0.timestamp >= range.start && $0.timestamp < range.end &&
            $0.value.map({ $0.isFinite && $0 >= 0 }) == true
        }
        var result: [DailyHabitTotal] = []
        for kind in HabitKind.allCases {
            let grouped = Dictionary(grouping: valid.filter { $0.kind == kind }) { calendar.startOfDay(for: $0.timestamp) }
            for day in grouped.keys.sorted() {
                let values = grouped[day]!.compactMap(\.value)
                // A mood scale is ordinal, so its daily value is a median rather than a sum.
                let total = kind == .mood ? (DomainUtilities.median(values) ?? 0) : values.reduce(0, +)
                guard total.isFinite else { continue }
                result.append(DailyHabitTotal(day: day, kind: kind, total: total, entryCount: values.count))
            }
        }
        return result.sorted { $0.day != $1.day ? $0.day < $1.day : $0.kind.rawValue < $1.kind.rawValue }
    }
    public func compare(kind: HabitKind, samples: [HealthSample], habits: [HabitEntry], range: DateInterval, calendar: Calendar) -> HabitComparison {
        let candidates = DomainUtilities.uniqueSamples(samples).filter {
            $0.kind == .sdnn && $0.value > 0 && $0.start >= range.start && $0.start < range.end
        }
        guard let source = DomainUtilities.primarySource(in: candidates) else {
            return HabitComparison(kind: kind, status: .informationInsufficient)
        }
        let grouped = Dictionary(grouping: candidates.filter { $0.sourceID == source }) { calendar.startOfDay(for: $0.start) }
        let totals = dailyTotals(habits: habits, range: range, calendar: calendar).filter { $0.kind == kind }
        let paired: [(habit: Double, sdnn: Double)] = totals.compactMap { total in
            guard let samples = grouped[total.day], let sdnn = DomainUtilities.median(samples.map(\.value)) else { return nil }
            return (total.total, sdnn)
        }
        guard let threshold = DomainUtilities.median(paired.map(\.habit)) else {
            return HabitComparison(kind: kind, status: .informationInsufficient, sourceID: source)
        }
        let low = paired.filter { $0.habit <= threshold }, high = paired.filter { $0.habit > threshold }
        guard paired.count >= 14, low.count >= 5, high.count >= 5,
              Set(paired.map(\.habit)).count > 1, Set(paired.map(\.sdnn)).count > 1,
              let lowMedian = DomainUtilities.median(low.map(\.sdnn)), let highMedian = DomainUtilities.median(high.map(\.sdnn)) else {
            return HabitComparison(kind: kind, status: .informationInsufficient, pairedDayCount: paired.count,
                                   lowGroupCount: low.count, highGroupCount: high.count, sourceID: source)
        }
        let difference = highMedian - lowMedian
        let direction: HabitAssociationDirection = difference > 0 ? .higherSDNN : (difference < 0 ? .lowerSDNN : .noDifference)
        return HabitComparison(kind: kind, status: .association, pairedDayCount: paired.count,
                               lowGroupCount: low.count, highGroupCount: high.count, lowMedianSDNN: lowMedian,
                               highMedianSDNN: highMedian, difference: difference, direction: direction, sourceID: source)
    }
}
