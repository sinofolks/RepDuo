import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class GhostRaceTests: XCTestCase {
    func testRecorderSamplesAtFifteenPerSecondAndKeepsRepTimes() {
        var recorder = GhostRecorder()
        for frame in 0..<60 {
            recorder.record(joints(hipY: 0.5), at: Double(frame) / 60)
        }
        recorder.markRep(at: 0.4)
        recorder.markRep(at: 0.9)
        let track = recorder.track(exercise: .squat, duration: 1, recordedAt: Date())
        XCTAssertEqual(track?.poses.count, 15)
        XCTAssertEqual(track?.repTimes, [0.4, 0.9])
    }

    func testASetWithoutRepsLeavesNoGhost() {
        var recorder = GhostRecorder()
        recorder.record(joints(hipY: 0.5), at: 0)
        XCTAssertNil(recorder.track(exercise: .squat, duration: 5, recordedAt: Date()))
    }

    func testPoseBlendsBetweenSamplesAndStopsAtGaps() {
        let track = GhostTrack(
            exercise: .squat,
            recordedAt: Date(),
            repTimes: [1],
            duration: 3,
            poses: [pose(0, hipY: 0.4), pose(0.2, hipY: 0.6), pose(2, hipY: 0.5)]
        )
        XCTAssertEqual(track.pose(at: 0.1)?[.leftHip]?.y ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertNil(track.pose(at: 1), "a 1.8 s gap is not bridged")
        XCTAssertNil(track.pose(at: 2.5), "no pose after the last sample")
    }

    func testRaceStatusTracksTheLeadAndTheGhostsFinish() {
        let track = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2, 3], duration: 3.5, poses: [])
        XCTAssertEqual(GhostRaceStatus(track: track, liveReps: 1, elapsed: 2.5).lead, -1)
        XCTAssertEqual(GhostRaceStatus(track: track, liveReps: 3, elapsed: 2.5).lead, 1)
        let after = GhostRaceStatus(track: track, liveReps: 4, elapsed: 4)
        XCTAssertTrue(after.ghostFinished)
        XCTAssertEqual(after.ghostReps, 3)
    }

    func testMoreRepsOrAQuickerEqualSetReplacesTheGhost() {
        let current = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2], duration: 10, poses: [])
        let more = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2, 3], duration: 20, poses: [])
        let quicker = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2], duration: 8, poses: [])
        let slower = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2], duration: 12, poses: [])
        XCTAssertTrue(more.beats(current))
        XCTAssertTrue(quicker.beats(current))
        XCTAssertFalse(slower.beats(current))
        XCTAssertTrue(slower.beats(nil))
    }

    func testGhostRoundTripsThroughJSON() throws {
        var recorder = GhostRecorder()
        recorder.record(joints(hipY: 0.123456789), at: 0)
        recorder.markRep(at: 0.5)
        let track = try XCTUnwrap(recorder.track(exercise: .lunge, duration: 1, recordedAt: Date(timeIntervalSince1970: 0)))
        let decoded = try JSONDecoder().decode(GhostTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(decoded, track)
        XCTAssertEqual(decoded.poses.first?.points["leftHip"]?[1], 0.1235)
    }

    func testSessionRacesItsGhostOnActiveTimeAndRecordsANewOne() {
        let ghost = GhostTrack(exercise: .squat, recordedAt: Date(), repTimes: [1, 2, 3], duration: 3, poses: [])
        let session = WorkoutSession(exercise: .squat, ghost: ghost, monotonicStart: 0)
        session.registerDebugRep(at: 0.5)
        session.pause(at: 1)
        session.resume(at: 11)
        // Ten paused seconds don't count, so the ghost is only at 1.5 s.
        XCTAssertEqual(session.ghostStatus(at: 11.5)?.ghostReps, 1)
        XCTAssertEqual(session.ghostStatus(at: 11.5)?.lead, 0)
        XCTAssertEqual(session.finish(monotonicTime: 12).ghostTrack?.repTimes, [0.5])
    }

    func testGhostForAnotherExerciseIsIgnored() {
        let ghost = GhostTrack(exercise: .pushUp, recordedAt: Date(), repTimes: [1], duration: 1, poses: [])
        XCTAssertNil(WorkoutSession(exercise: .squat, ghost: ghost, monotonicStart: 0).ghost)
    }

    private func joints(hipY: Double) -> [BodyJoint: JointPoint] {
        [.leftHip: JointPoint(x: 0.5, y: hipY, confidence: 0.9), .leftKnee: JointPoint(x: 0.5, y: 0.3, confidence: 0.9)]
    }

    private func pose(_ time: Double, hipY: Double) -> GhostTrack.Pose {
        GhostTrack.Pose(time: time, points: ["leftHip": [0.5, hipY]])
    }
}
