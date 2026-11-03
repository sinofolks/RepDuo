import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class MovementCoachTests: XCTestCase {
    func testFirstThreeClearRepsBuildPersonalBaseline() {
        let coach = MovementCoach(exercise: .squat, trackingMode: .fullBody)

        let first = assessRep(coach, rep: 1, start: 0, minimumAngle: 90)
        let second = assessRep(coach, rep: 2, start: 2, minimumAngle: 88)
        let third = assessRep(coach, rep: 3, start: 4, minimumAngle: 91)
        let fourth = assessRep(coach, rep: 4, start: 6, minimumAngle: 89)

        XCTAssertNotNil(first.score)
        XCTAssertFalse(first.isPersonalized)
        XCTAssertEqual(second.baselineProgress, 2)
        XCTAssertEqual(third.baselineProgress, 3)
        XCTAssertTrue(coach.baseline.isPersonalized)
        XCTAssertTrue(fourth.isPersonalized)
    }

    func testInsufficientVisibilityCountsWithoutInventingScore() {
        let coach = MovementCoach(exercise: .pushUp, trackingMode: .partialBody)
        let result = coach.process(
            frame: PoseFrame(timestamp: 1, quality: .usable, primaryAngle: 100),
            phase: .up,
            completedRep: true,
            repNumber: 1
        )

        XCTAssertNil(result?.score)
        XCTAssertNil(result?.rangeScore)
        XCTAssertFalse(result?.shouldSpeak ?? true)
    }

    func testVoiceCueRequiresSameIssueTwiceInARow() {
        let coach = MovementCoach(exercise: .squat, trackingMode: .fullBody)
        let first = assessRep(coach, rep: 1, start: 0, minimumAngle: 148)
        let second = assessRep(coach, rep: 2, start: 2, minimumAngle: 149)

        XCTAssertEqual(first.primaryIssue, .shallowRange)
        XCTAssertFalse(first.shouldSpeak)
        XCTAssertEqual(second.primaryIssue, .shallowRange)
        XCTAssertTrue(second.shouldSpeak)
    }

    func testReportDetectsLateSetRangeFading() {
        let coach = MovementCoach(exercise: .squat, trackingMode: .fullBody)
        [88.0, 90, 89, 125, 128, 130].enumerated().forEach { index, minimumAngle in
            _ = assessRep(
                coach,
                rep: index + 1,
                start: Double(index) * 2,
                minimumAngle: minimumAngle
            )
        }

        let report = coach.report()
        XCTAssertEqual(report.scoredRepCount, 6)
        XCTAssertTrue(report.detectedFatigue)
        XCTAssertEqual(report.primaryIssue, .rangeFading)
    }

    private func assessRep(
        _ coach: MovementCoach,
        rep: Int,
        start: TimeInterval,
        minimumAngle: Double
    ) -> RepCoachingResult {
        _ = coach.process(
            frame: PoseFrame(timestamp: start, quality: .excellent, primaryAngle: 170),
            phase: .down,
            completedRep: false,
            repNumber: rep - 1
        )
        _ = coach.process(
            frame: PoseFrame(timestamp: start + 0.4, quality: .excellent, primaryAngle: 135),
            phase: .down,
            completedRep: false,
            repNumber: rep - 1
        )
        _ = coach.process(
            frame: PoseFrame(timestamp: start + 0.8, quality: .excellent, primaryAngle: minimumAngle),
            phase: .hold,
            completedRep: false,
            repNumber: rep - 1
        )
        return coach.process(
            frame: PoseFrame(timestamp: start + 1.2, quality: .excellent, primaryAngle: 170),
            phase: .up,
            completedRep: true,
            repNumber: rep
        )!
    }
}
