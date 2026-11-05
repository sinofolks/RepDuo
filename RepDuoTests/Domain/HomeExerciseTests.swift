import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class HomeExerciseTests: XCTestCase {
    func testLungeFollowsTheDeeperKnee() {
        let joints: [BodyJoint: JointPoint] = [
            // Front leg bent to 90°.
            .leftHip: point(0.5, 0.6), .leftKnee: point(0.7, 0.6), .leftAnkle: point(0.7, 0.4),
            // Back leg nearly straight.
            .rightHip: point(0.5, 0.6), .rightKnee: point(0.4, 0.4), .rightAnkle: point(0.3, 0.2)
        ]
        let measurement = PoseMeasurementBuilder.measurement(for: .lunge, joints: joints)
        XCTAssertEqual(measurement.angle ?? 0, 90, accuracy: 0.5)
        XCTAssertTrue(measurement.formAcceptable)
    }

    func testGluteBridgeReadsRestingHighAndTheLiftLow() {
        let lying = PoseMeasurementBuilder.measurement(for: .gluteBridge, joints: hipJoints(angle: 135))
        let lifted = PoseMeasurementBuilder.measurement(for: .gluteBridge, joints: hipJoints(angle: 178))
        XCTAssertEqual(lying.angle ?? 0, 170, accuracy: 0.5)
        XCTAssertEqual(lifted.angle ?? 0, 127, accuracy: 0.5)
    }

    func testSitUpUsesTheRawHipAngle() {
        let measurement = PoseMeasurementBuilder.measurement(for: .sitUp, joints: hipJoints(angle: 70))
        XCTAssertEqual(measurement.angle ?? 0, 70, accuracy: 0.5)
    }

    func testJumpingJackFlipsArmRaise() {
        let down = PoseMeasurementBuilder.measurement(for: .jumpingJack, joints: armJoints(wristY: 0.45))
        let up = PoseMeasurementBuilder.measurement(for: .jumpingJack, joints: armJoints(wristY: 0.95))
        XCTAssertEqual(down.angle ?? 0, 180, accuracy: 0.5)
        XCTAssertEqual(up.angle ?? 180, 0, accuracy: 0.5)
    }

    func testPartialSitUpNeedsOnlyOneShoulderHipAndKnee() {
        let joints = hipJoints(angle: 130).filter { $0.key != .leftAnkle }
        let quality = PoseQualityEvaluator.evaluate(exercise: .sitUp, joints: joints, trackingMode: .partialBody)
        XCTAssertTrue(quality.quality.permitsCounting)
        XCTAssertEqual(quality.requiredJoints, [.leftShoulder, .leftHip, .leftKnee])
    }

    func testEveryNewMoveCountsOneFullCycle() {
        let cycles: [ExerciseType: [Double]] = [
            .lunge: [165, 165, 138, 136, 100, 98, 128, 130, 160, 162],
            .gluteBridge: [170, 170, 146, 144, 128, 127, 145, 148, 166, 168],
            .sitUp: [130, 130, 105, 100, 65, 62, 92, 96, 125, 128],
            .jumpingJack: [170, 170, 120, 110, 30, 20, 90, 100, 160, 165]
        ]
        for (exercise, angles) in cycles {
            let engine = RepDetectionEngine(exercise: exercise)
            for (index, angle) in angles.enumerated() {
                _ = engine.process(PoseFrame(timestamp: Double(index) * 0.15, quality: .excellent, primaryAngle: angle))
            }
            XCTAssertEqual(engine.repCount, 1, "\(exercise)")
        }
    }

    private func point(_ x: Double, _ y: Double) -> JointPoint {
        JointPoint(x: x, y: y, confidence: 0.95)
    }

    /// Left-side shoulder–hip–knee at `angle`, with the shoulder on the floor line.
    private func hipJoints(angle: Double) -> [BodyJoint: JointPoint] {
        let radians = angle * .pi / 180
        return [
            .leftShoulder: point(0.2, 0.5),
            .leftHip: point(0.5, 0.5),
            .leftKnee: point(0.5 - 0.25 * cos(radians), 0.5 + 0.25 * sin(radians)),
            .leftAnkle: point(0.8, 0.5)
        ]
    }

    private func armJoints(wristY: Double) -> [BodyJoint: JointPoint] {
        [
            .leftShoulder: point(0.4, 0.7), .leftHip: point(0.4, 0.4), .leftWrist: point(0.4, wristY),
            .rightShoulder: point(0.6, 0.7), .rightHip: point(0.6, 0.4), .rightWrist: point(0.6, wristY)
        ]
    }
}
