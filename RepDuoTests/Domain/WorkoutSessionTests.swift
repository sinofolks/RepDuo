import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class WorkoutSessionTests: XCTestCase {
    func testPausedTimeIsExcludedFromSummary() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let session = WorkoutSession(exercise: .squat, startedAt: startDate, monotonicStart: 100)
        session.pause(at: 102)
        session.resume(at: 105)
        let summary = session.finish(at: startDate.addingTimeInterval(10), monotonicTime: 110)
        XCTAssertEqual(summary.activeDuration, 7, accuracy: 0.001)
    }

    func testDebugRepUpdatesViewState() {
        let session = WorkoutSession(exercise: .pushUp, monotonicStart: 10)
        session.registerDebugRep()
        XCTAssertEqual(session.state.repCount, 1)
        XCTAssertEqual(session.state.poseQuality, .excellent)
        XCTAssertEqual(session.state.lastRepCoaching?.score, 94)
        XCTAssertEqual(session.finish(monotonicTime: 12).coachingReport?.scoredRepCount, 1)
    }

    func testPausePreventsIncomingFramesFromCounting() {
        let session = WorkoutSession(exercise: .squat, monotonicStart: 10)
        session.pause(at: 11)
        session.process(PoseFrame(timestamp: 12, quality: .excellent, primaryAngle: 170))
        session.process(PoseFrame(timestamp: 12.1, quality: .excellent, primaryAngle: 170))
        session.registerDebugRep()
        XCTAssertEqual(session.state.repCount, 0)
    }

    func testSummaryCalculatesAverageAndMaximumHeartRate() {
        let session = WorkoutSession(exercise: .squat, monotonicStart: 10)
        session.updateHeartRate(120)
        session.updateHeartRate(150)
        session.updateHeartRate(-1)
        let summary = session.finish(monotonicTime: 20)
        XCTAssertEqual(summary.averageHeartRate, 135)
        XCTAssertEqual(summary.maximumHeartRate, 150)
    }

    func testLowConfidenceEventsCountTransitionsRatherThanFrames() {
        let session = WorkoutSession(exercise: .squat, monotonicStart: 0)
        session.process(PoseFrame(timestamp: 0.1, quality: .excellent, primaryAngle: 170))
        session.process(PoseFrame(timestamp: 0.2, quality: .unstable, primaryAngle: nil))
        session.process(PoseFrame(timestamp: 0.3, quality: .unstable, primaryAngle: nil))
        session.process(PoseFrame(timestamp: 0.4, quality: .excellent, primaryAngle: 170))
        session.process(PoseFrame(timestamp: 0.5, quality: .multiplePeople, primaryAngle: nil))
        let summary = session.finish(monotonicTime: 1)
        XCTAssertEqual(summary.lowConfidenceEventCount, 2)
    }
}
