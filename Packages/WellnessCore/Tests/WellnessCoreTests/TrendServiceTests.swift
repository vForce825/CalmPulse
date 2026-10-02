import Foundation
import XCTest
@testable import WellnessCore

final class TrendServiceTests: XCTestCase {
    private let service = TrendService()
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var start: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 1))! }
    private func sample(day: Int, value: Double = 20) -> HealthSample {
        let date = cal.date(byAdding: .day, value: day, to: start)!.addingTimeInterval(3600)
        return HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-A", start: date, end: date, value: value)
    }
    func testSparsePointsPreserveMissingDayAndCoverage() {
        let samples = [sample(day: 0), sample(day: 2)]
        let range = DateInterval(start: start, end: cal.date(byAdding: .day, value: 3, to: start)!)
        let report = service.summarize(samples: samples, assessments: [], habits: [], range: range, calendar: cal)
        XCTAssertEqual(report.points.count, 2)
        XCTAssertEqual(report.points.map(\.observedAt), samples.map(\.start))
        XCTAssertEqual(report.coverage.totalCivilDays, 3)
        XCTAssertEqual(report.coverage.coveredCivilDays, 2)
        XCTAssertEqual(report.coverage.fraction, 2.0 / 3, accuracy: 0.0001)
    }
    func testBandDistributionIsSampleShareAndDeduplicates() {
        let samples = (0..<4).map { sample(day: $0) }
        let scores = [80, 90, 75, 20]
        let assessments = zip(samples, scores).map { s, score in
            WellnessAssessment(score: score, sourceID: s.sourceID, sampleID: s.id, observedAt: s.start)
        }
        let range = DateInterval(start: start, end: cal.date(byAdding: .day, value: 7, to: start)!)
        let report = service.summarize(samples: samples + samples, assessments: assessments + assessments, habits: [], range: range, calendar: cal)
        let highest = report.bandDistribution.first { $0.band == .highest }
        XCTAssertEqual(highest?.sampleCount, 3)
        XCTAssertEqual(highest?.fraction, 0.75)
        XCTAssertEqual(report.coverage.sampleCount, 4)
        XCTAssertEqual(report.scoredSampleCount, 4)
    }
    func testEmptyRecordsRemainUnavailableAndHalfOpenRange() {
        let range = DateInterval(start: start, end: start.addingTimeInterval(86400))
        let report = service.summarize(samples: [], assessments: [], habits: [], range: range, calendar: cal)
        XCTAssertEqual(report.sleep.availability, .unavailable)
        XCTAssertEqual(report.activities.availability, .unavailable)
        XCTAssertEqual(report.coverage.coveredCivilDays, 0)
        let atEnd = HealthSample(id: UUID(), kind: .sdnn, sourceID: "synthetic-A", start: range.end, end: range.end, value: 20)
        XCTAssertTrue(service.summarize(samples: [atEnd], assessments: [], habits: [], range: range, calendar: cal).points.isEmpty)
    }
    func testDayWeekMonthAndYearRangesAndWeeklyReport() {
        for component in [Calendar.Component.day, .weekOfYear, .month, .year] {
            let range = cal.dateInterval(of: component, for: start)!
            let report = service.summarize(samples: [sample(day: 0)], assessments: [], habits: [], range: range, calendar: cal)
            XCTAssertGreaterThanOrEqual(report.coverage.totalCivilDays, 1)
            XCTAssertEqual(report.coverage.sampleCount, 1)
            XCTAssertEqual(report.weeklyReports.reduce(0) { $0 + $1.sampleCount }, 1)
        }
    }
    func testHabitTotalsRespectCivilDaysRevisionsAndTombstones() {
        let id = UUID()
        let entries = [
            HabitEntry(id: id, kind: .waterML, timestamp: start.addingTimeInterval(100), value: 200, note: nil, revision: 1, origin: "watch", deleted: false),
            HabitEntry(id: id, kind: .waterML, timestamp: start.addingTimeInterval(100), value: nil, note: nil, revision: 2, origin: "watch", deleted: true),
            HabitEntry(id: UUID(), kind: .waterML, timestamp: start.addingTimeInterval(86399), value: 250, note: nil, revision: 1, origin: "phone", deleted: false),
            HabitEntry(id: UUID(), kind: .caffeineMG, timestamp: start.addingTimeInterval(86400), value: 80, note: nil, revision: 1, origin: "phone", deleted: false)
        ]
        let report = service.summarize(samples: [], assessments: [], habits: entries, range: DateInterval(start: start, end: start.addingTimeInterval(172800)), calendar: cal)
        XCTAssertEqual(report.habitTotals.first { $0.kind == .waterML }?.total, 250)
        XCTAssertEqual(report.habitTotals.first { $0.kind == .caffeineMG }?.day, start.addingTimeInterval(86400))
        XCTAssertEqual(report.habitTotals.count, 2)
    }
    func testWeeklyActivityUsesSameChosenSourceAsWholeRange() {
        let secondWeek = cal.date(byAdding: .day, value: 8, to: start)!
        let records = [
            HealthSample(id: UUID(), kind: .steps, sourceID: "A", start: start, end: start, value: 100),
            HealthSample(id: UUID(), kind: .steps, sourceID: "B", start: secondWeek, end: secondWeek, value: 200),
            HealthSample(id: UUID(), kind: .steps, sourceID: "B", start: secondWeek.addingTimeInterval(60), end: secondWeek.addingTimeInterval(60), value: 300)
        ]
        let report = service.summarize(samples: records, assessments: [], habits: [], range: DateInterval(start: start, end: cal.date(byAdding: .day, value: 14, to: start)!), calendar: cal)
        XCTAssertEqual(report.activities.sourceIDs[.steps], "B")
        XCTAssertEqual(report.activities.daily.compactMap(\.steps).reduce(0, +), 500)
        XCTAssertEqual(report.weeklyReports.compactMap(\.steps).reduce(0, +), 500)
    }
    func testUnrelatedAssessmentCannotHideMatchingAssessment() {
        let reading = sample(day: 0)
        let unrelated = WellnessAssessment(score: nil, sourceID: "other-source", sampleID: reading.id, observedAt: reading.start)
        let matching = WellnessAssessment(score: 80, sourceID: reading.sourceID, sampleID: reading.id, observedAt: reading.start)
        let report = service.summarize(samples: [reading], assessments: [unrelated, matching], habits: [], range: DateInterval(start: start, end: start.addingTimeInterval(86400)), calendar: cal)
        XCTAssertEqual(report.points.first?.score, 80)
        XCTAssertEqual(report.points.first?.version, "wellness-sdnn-v1")
    }

}
