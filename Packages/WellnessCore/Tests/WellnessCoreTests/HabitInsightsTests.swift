import Foundation
import XCTest
@testable import WellnessCore

final class HabitInsightsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var start: Date { Date(timeIntervalSince1970: 0) }
    private func fixture(days: Int, variableSDNN: Bool = true, variableHabit: Bool = true, highDays: Int? = nil) -> ([HealthSample], [HabitEntry]) {
        let high = highDays ?? days / 2
        return ((0..<days).map { day in
            let date = cal.date(byAdding: .day, value: day, to: start)!.addingTimeInterval(3600)
            return HealthSample(id: UUID(), kind: .sdnn, sourceID: "A", start: date, end: date, value: variableSDNN && day < high ? 30 : 20)
        }, (0..<days).map { day in
            HabitEntry(id: UUID(), kind: .caffeineMG, timestamp: cal.date(byAdding: .day, value: day, to: start)!, value: variableHabit && day < high ? 200 : 0, note: nil, revision: 1, origin: "phone", deleted: false)
        })
    }
    private func compare(_ samples: [HealthSample], _ habits: [HabitEntry], days: Int = 30) -> HabitComparison {
        HabitInsights().compare(kind: .caffeineMG, samples: samples, habits: habits, range: DateInterval(start: start, end: cal.date(byAdding: .day, value: days, to: start)!), calendar: cal)
    }
    func testFourteenPairedDaysAndFivePerGroupAllowDescriptiveAssociation() {
        let (samples, habits) = fixture(days: 14)
        let result = compare(samples, habits)
        XCTAssertEqual(result.status, .association)
        XCTAssertEqual(result.pairedDayCount, 14)
        XCTAssertEqual(result.lowGroupCount, 7)
        XCTAssertEqual(result.highGroupCount, 7)
        XCTAssertEqual(result.lowMedianSDNN, 20)
        XCTAssertEqual(result.highMedianSDNN, 30)
        XCTAssertEqual(result.difference, 10)
        XCTAssertEqual(result.direction, .higherSDNN)
        XCTAssertEqual(result.caveat, "相关不代表因果")
    }
    func testThirteenDaysOrFourInGroupRemainInsufficient() {
        let (samples, habits) = fixture(days: 13)
        XCTAssertEqual(compare(samples, habits).status, .informationInsufficient)
        let (imbalancedSamples, imbalancedHabits) = fixture(days: 14, highDays: 4)
        XCTAssertEqual(compare(imbalancedSamples, imbalancedHabits).status, .informationInsufficient)
    }
    func testConstantHabitOrSDNNDoesNotCreateAssociation() {
        let (samples, habits) = fixture(days: 14, variableHabit: false)
        XCTAssertEqual(compare(samples, habits).status, .informationInsufficient)
        let (constantSamples, variedHabits) = fixture(days: 14, variableSDNN: false)
        XCTAssertEqual(compare(constantSamples, variedHabits).status, .informationInsufficient)
    }
    func testMissingHabitDaysAreNotAssumedZeroAndSourcesRemainIsolated() {
        let (samples, habits) = fixture(days: 14)
        XCTAssertEqual(compare(samples, Array(habits.dropLast())).pairedDayCount, 13)
        let switched = samples.enumerated().map { offset, s in
            HealthSample(id: s.id, kind: s.kind, sourceID: offset < 7 ? "A" : "B", start: s.start, end: s.end, value: s.value)
        }
        XCTAssertEqual(compare(switched, habits).status, .informationInsufficient)
        XCTAssertEqual(compare(switched, habits).pairedDayCount, 7)
    }
    func testTombstoneWinsSameRevisionAndCivilDayTotalsExcludeInvalidValues() {
        let date = start.addingTimeInterval(86399)
        let id = UUID()
        let entries = [
            HabitEntry(id: id, kind: .waterML, timestamp: date, value: 250, note: nil, revision: 2, origin: "z-watch", deleted: false),
            HabitEntry(id: id, kind: .waterML, timestamp: date, value: nil, note: nil, revision: 2, origin: "a-phone", deleted: true),
            HabitEntry(id: UUID(), kind: .waterML, timestamp: date, value: 500, note: nil, revision: 1, origin: "phone", deleted: false),
            HabitEntry(id: UUID(), kind: .waterML, timestamp: date, value: -1, note: nil, revision: 1, origin: "phone", deleted: false)
        ]
        let totals = HabitInsights().dailyTotals(habits: entries, range: DateInterval(start: start, end: start.addingTimeInterval(86400)), calendar: cal)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.first?.day, start)
        XCTAssertEqual(totals.first?.total, 500)
        XCTAssertEqual(totals.first?.entryCount, 1)
    }
}
