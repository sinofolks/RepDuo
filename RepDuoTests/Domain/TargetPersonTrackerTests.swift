import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class TargetPersonTrackerTests: XCTestCase {
    func testLocksOntoProminentCenteredPersonAndCountsSmallBystander() {
        let tracker = TargetPersonTracker()
        let trainee = person(centerX: 0.5, height: 0.7)
        let bystander = person(centerX: 0.9, height: 0.3)

        let result = tracker.update(candidates: [bystander, trainee], at: 0)

        XCTAssertEqual(result.status, .locked)
        XCTAssertEqual(result.targetIndex, 1)
        XCTAssertEqual(result.bystanderCount, 1)
    }

    func testDoesNotGuessBetweenTwoEquallyProminentPeople() {
        let tracker = TargetPersonTracker()

        let result = tracker.update(
            candidates: [person(centerX: 0.45, height: 0.6), person(centerX: 0.55, height: 0.6)],
            at: 0
        )

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertNil(result.targetIndex)
    }

    func testIgnoresFragmentDetections() {
        let tracker = TargetPersonTracker()
        let fragment = PoseCandidate(joints: [
            .leftWrist: JointPoint(x: 0.5, y: 0.5, confidence: 0.9),
            .leftElbow: JointPoint(x: 0.52, y: 0.55, confidence: 0.9)
        ])!

        let result = tracker.update(candidates: [person(centerX: 0.3, height: 0.6), fragment], at: 0)

        XCTAssertEqual(result.targetIndex, 0)
        XCTAssertEqual(result.bystanderCount, 0)
    }

    func testFollowsTraineeWhileBystanderWalksAcrossTheBackground() {
        let tracker = TargetPersonTracker()
        _ = tracker.update(candidates: [person(centerX: 0.5, height: 0.7)], at: 0)

        for step in 1...20 {
            let time = Double(step) * 0.1
            let bystander = person(centerX: 0.05 + Double(step) * 0.045, height: 0.35)
            // Vision gives no stable order, so alternate where the trainee appears.
            let trainee = person(centerX: 0.5, height: 0.7 - 0.2 * sin(time * 3))
            let candidates = step.isMultiple(of: 2) ? [trainee, bystander] : [bystander, trainee]

            let result = tracker.update(candidates: candidates, at: time)

            XCTAssertEqual(result.status, .locked, "step \(step)")
            XCTAssertEqual(result.targetIndex, step.isMultiple(of: 2) ? 0 : 1, "step \(step)")
            XCTAssertEqual(result.bystanderCount, 1, "step \(step)")
        }
    }

    func testDoesNotJumpToBystanderWhileTraineeIsBrieflyHidden() {
        let tracker = TargetPersonTracker()
        _ = tracker.update(candidates: [person(centerX: 0.5, height: 0.7), person(centerX: 0.85, height: 0.3)], at: 0)

        let hidden = tracker.update(candidates: [person(centerX: 0.85, height: 0.3)], at: 0.5)
        XCTAssertEqual(hidden.status, .searching)
        XCTAssertNil(hidden.targetIndex)
        XCTAssertEqual(hidden.bystanderCount, 1)

        let back = tracker.update(candidates: [person(centerX: 0.85, height: 0.3), person(centerX: 0.52, height: 0.7)], at: 1)
        XCTAssertEqual(back.targetIndex, 1)
        XCTAssertEqual(back.trackID, hidden.trackID)
    }

    func testReacquisitionPrefersSomeoneTheTraineesSize() {
        let tracker = TargetPersonTracker()
        _ = tracker.update(candidates: [person(centerX: 0.5, height: 0.7)], at: 0)

        // The trainee leaves long enough to release the lock; only a much smaller person remains.
        let small = tracker.update(candidates: [person(centerX: 0.5, height: 0.25)], at: 2)
        XCTAssertNil(small.targetIndex)

        let returned = tracker.update(candidates: [person(centerX: 0.5, height: 0.25), person(centerX: 0.3, height: 0.68)], at: 2.5)
        XCTAssertEqual(returned.targetIndex, 1)
    }

    func testPausesWhenTwoPeopleOverlapTheTrainee() {
        let tracker = TargetPersonTracker()
        _ = tracker.update(candidates: [person(centerX: 0.5, height: 0.7)], at: 0)

        let result = tracker.update(
            candidates: [person(centerX: 0.49, height: 0.7), person(centerX: 0.51, height: 0.7)],
            at: 0.1
        )

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertNil(result.targetIndex)
    }

    func testResetStartsANewTrack() {
        let tracker = TargetPersonTracker()
        let first = tracker.update(candidates: [person(centerX: 0.5, height: 0.7)], at: 0)
        tracker.reset()
        let second = tracker.update(candidates: [person(centerX: 0.5, height: 0.7)], at: 0.1)

        XCTAssertEqual(second.status, .locked)
        XCTAssertEqual(second.trackID, first.trackID + 1)
    }

    /// Upright stick figure whose feet sit at y = 0.1 and whose width scales with height.
    private func person(centerX: Double, height: Double, confidence: Double = 0.8) -> PoseCandidate {
        let bottom = 0.1
        let half = height * 0.18
        func point(_ dx: Double, _ fraction: Double) -> JointPoint {
            JointPoint(x: centerX + dx * half, y: bottom + fraction * height, confidence: confidence)
        }
        return PoseCandidate(joints: [
            .nose: point(0, 1),
            .neck: point(0, 0.85),
            .leftShoulder: point(-1, 0.82), .rightShoulder: point(1, 0.82),
            .leftElbow: point(-1.3, 0.65), .rightElbow: point(1.3, 0.65),
            .leftWrist: point(-1.4, 0.5), .rightWrist: point(1.4, 0.5),
            .leftHip: point(-0.6, 0.5), .rightHip: point(0.6, 0.5),
            .leftKnee: point(-0.6, 0.25), .rightKnee: point(0.6, 0.25),
            .leftAnkle: point(-0.6, 0), .rightAnkle: point(0.6, 0)
        ])!
    }
}
