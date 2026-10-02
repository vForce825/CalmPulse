import Foundation
import XCTest
@testable import WellnessCore
final class BreathingTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    func testWallClockSurvivesNoTicksAndRestore() throws {
        var session = BreathingSession()
        session.start(durationSeconds: 120, at: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(45)), 75)
        let restored = try JSONDecoder().decode(BreathingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(75)), 45)
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(200)), 0)
    }
    func testPauseResumeAndStop() {
        var session = BreathingSession()
        session.start(durationSeconds: 60, at: start)
        session.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(80)), 40)
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(110)), 30)
        session.stop()
        XCTAssertEqual(session.remaining(at: start), 0)
    }
    func testInvalidDurationAndClockRollbackAreBounded() {
        var session = BreathingSession()
        session.start(durationSeconds: -3, at: start)
        XCTAssertEqual(session.remaining(at: start), 0)
        session.start(durationSeconds: 60, at: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(-10)), 60)
    }
}
