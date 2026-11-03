import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class PoseProcessingTests: XCTestCase {
    func testPushUpQualityAcceptsACompleteRightSide() {
        let joints = pushUpJoints(side: .right, hipOffset: 0)
        let evaluation = PoseQualityEvaluator.evaluate(exercise: .pushUp, joints: joints)
        XCTAssertEqual(evaluation.quality, .excellent)
        XCTAssertTrue(evaluation.requiredJoints.contains(.rightElbow))
    }

    func testPushUpQualityRejectsAnIncompleteSide() {
        var joints = pushUpJoints(side: .left, hipOffset: 0)
        joints.removeValue(forKey: .leftWrist)
        XCTAssertEqual(
            PoseQualityEvaluator.evaluate(exercise: .pushUp, joints: joints).quality,
            .missingRequiredJoints
        )
    }

    func testFrontalPushUpQualityPrefersBothArmsAndFullBody() {
        let evaluation = PoseQualityEvaluator.evaluate(
            exercise: .pushUp,
            joints: frontalPushUpJoints(leftBent: false, rightBent: false)
        )

        XCTAssertEqual(evaluation.quality, .excellent)
        XCTAssertTrue(evaluation.requiredJoints.contains(.leftElbow))
        XCTAssertTrue(evaluation.requiredJoints.contains(.rightElbow))
        XCTAssertTrue(evaluation.requiredJoints.contains(.leftHip))
        XCTAssertTrue(evaluation.requiredJoints.contains(.rightHip))
    }

    func testFrontalPushUpFusesBothElbowAngles() {
        let top = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: frontalPushUpJoints(leftBent: false, rightBent: false)
        )
        let bottom = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: frontalPushUpJoints(leftBent: true, rightBent: true)
        )

        XCTAssertEqual(top.angle ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(bottom.angle ?? 0, 90, accuracy: 0.001)
        XCTAssertTrue(top.formAcceptable)
        XCTAssertTrue(bottom.formAcceptable)
    }

    func testAccurateFrontalPushUpRejectsUnsynchronizedArms() {
        let joints = frontalPushUpJoints(leftBent: true, rightBent: false)
        let accurate = PoseMeasurementBuilder.measurement(for: .pushUp, joints: joints)
        let rough = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: joints,
            trackingMode: .partialBody
        )

        XCTAssertFalse(accurate.formAcceptable)
        XCTAssertTrue(rough.formAcceptable)
        XCTAssertEqual(accurate.angle ?? 0, 135, accuracy: 0.001)
    }

    func testFrontalPushUpMotionRequiresTorsoTravelAndElbowFlexion() {
        var estimator = PushUpMotionEstimator()
        let topJoints = realisticFrontalPushUp(shoulderY: 0.65, hipY: 0.55, elbowsBent: false)
        let topRaw = PoseMeasurementBuilder.measurement(for: .pushUp, joints: topJoints)
        _ = estimator.refine(topRaw, joints: topJoints, trackingMode: .fullBody, timestamp: 0)
        let top = estimator.refine(topRaw, joints: topJoints, trackingMode: .fullBody, timestamp: 0.1)

        let armOnlyJoints = realisticFrontalPushUp(shoulderY: 0.65, hipY: 0.55, elbowsBent: true)
        let armOnlyRaw = PoseMeasurementBuilder.measurement(for: .pushUp, joints: armOnlyJoints)
        let armOnly = estimator.refine(
            armOnlyRaw,
            joints: armOnlyJoints,
            trackingMode: .fullBody,
            timestamp: 0.2
        )

        let torsoOnlyJoints = realisticFrontalPushUp(shoulderY: 0.46, hipY: 0.36, elbowsBent: false)
        let torsoOnlyRaw = PoseMeasurementBuilder.measurement(for: .pushUp, joints: torsoOnlyJoints)
        let torsoOnly = estimator.refine(
            torsoOnlyRaw,
            joints: torsoOnlyJoints,
            trackingMode: .fullBody,
            timestamp: 0.3
        )

        let bottomJoints = realisticFrontalPushUp(shoulderY: 0.46, hipY: 0.36, elbowsBent: true)
        let bottomRaw = PoseMeasurementBuilder.measurement(for: .pushUp, joints: bottomJoints)
        let bottom = estimator.refine(
            bottomRaw,
            joints: bottomJoints,
            trackingMode: .fullBody,
            timestamp: 0.4
        )

        XCTAssertGreaterThanOrEqual(top.angle ?? 0, 160)
        XCTAssertGreaterThan(armOnly.angle ?? 0, 142)
        XCTAssertGreaterThan(torsoOnly.angle ?? 0, 100)
        XCTAssertLessThanOrEqual(bottom.angle ?? 180, 100)
    }

    func testFrontalPushUpMotionCompletesAFullMultiSignalCycle() {
        var estimator = PushUpMotionEstimator()
        let engine = RepDetectionEngine(exercise: .pushUp)
        let poses: [(Double, Double, Bool)] = [
            (0.65, 0.55, false), (0.65, 0.55, false),
            (0.54, 0.44, true), (0.54, 0.44, true),
            (0.46, 0.36, true), (0.46, 0.36, true),
            (0.60, 0.50, false), (0.60, 0.50, false),
            (0.65, 0.55, false), (0.65, 0.55, false)
        ]

        for (index, pose) in poses.enumerated() {
            let joints = realisticFrontalPushUp(
                shoulderY: pose.0,
                hipY: pose.1,
                elbowsBent: pose.2
            )
            let raw = PoseMeasurementBuilder.measurement(for: .pushUp, joints: joints)
            let refined = estimator.refine(
                raw,
                joints: joints,
                trackingMode: .fullBody,
                timestamp: Double(index) * 0.15
            )
            _ = engine.process(PoseFrame(
                timestamp: Double(index) * 0.15,
                joints: joints,
                quality: .excellent,
                primaryAngle: refined.angle,
                isFormAcceptable: refined.formAcceptable
            ))
        }

        XCTAssertEqual(engine.repCount, 1)
    }

    func testPartialPushUpAcceptsArmJointsWithoutTheRestOfTheBody() {
        let joints: [BodyJoint: JointPoint] = [
            .leftShoulder: JointPoint(x: 0.3, y: 0.6, confidence: 0.95),
            .leftElbow: JointPoint(x: 0.5, y: 0.5, confidence: 0.95),
            .leftWrist: JointPoint(x: 0.7, y: 0.4, confidence: 0.95)
        ]

        XCTAssertEqual(
            PoseQualityEvaluator.evaluate(exercise: .pushUp, joints: joints).quality,
            .missingRequiredJoints
        )
        XCTAssertEqual(
            PoseQualityEvaluator.evaluate(
                exercise: .pushUp,
                joints: joints,
                trackingMode: .partialBody
            ).quality,
            .excellent
        )

        let measurement = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: joints,
            trackingMode: .partialBody
        )
        XCTAssertNotNil(measurement.angle)
        XCTAssertTrue(measurement.formAcceptable)
    }

    func testPartialSquatAcceptsOneHipKneeAndAnkleWithoutAHead() {
        var joints = squatJoints()
        joints.removeValue(forKey: .nose)

        XCTAssertEqual(
            PoseQualityEvaluator.evaluate(exercise: .squat, joints: joints).quality,
            .missingRequiredJoints
        )
        let partial = PoseQualityEvaluator.evaluate(
            exercise: .squat,
            joints: joints,
            trackingMode: .partialBody
        )
        XCTAssertEqual(partial.quality, .excellent)
        XCTAssertEqual(partial.requiredJoints, [.leftHip, .leftKnee, .leftAnkle])
    }

    func testMultiplePeopleAlwaysBlocksCountingQuality() {
        let evaluation = PoseQualityEvaluator.evaluate(
            exercise: .squat,
            joints: squatJoints(),
            personCount: 2
        )
        XCTAssertEqual(evaluation.quality, .multiplePeople)
    }

    func testPushUpMeasurementUsesOneConsistentBodySide() {
        let aligned = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: pushUpJoints(side: .right, hipOffset: 0)
        )
        let broken = PoseMeasurementBuilder.measurement(
            for: .pushUp,
            joints: pushUpJoints(side: .right, hipOffset: 0.3)
        )
        XCTAssertEqual(aligned.angle ?? 0, 180, accuracy: 0.001)
        XCTAssertTrue(aligned.formAcceptable)
        XCTAssertFalse(broken.formAcceptable)
    }

    func testSmootherReducesJitterAndResetsAfterTrackingGap() {
        let smoother = PoseSmoother(alpha: 0.5, resetInterval: 0.5)
        let first = [BodyJoint.nose: JointPoint(x: 0, y: 0, confidence: 1)]
        let second = [BodyJoint.nose: JointPoint(x: 1, y: 1, confidence: 0.8)]
        _ = smoother.smooth(first, at: 0)
        let blended = smoother.smooth(second, at: 0.1)
        XCTAssertEqual(blended[.nose]?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(blended[.nose]?.confidence, 0.8)

        let reset = smoother.smooth(second, at: 1)
        XCTAssertEqual(reset[.nose]?.x, 1)
    }

    func testSquatFramingRejectsAVisibleButTinyBody() {
        let joints: [BodyJoint: JointPoint] = [
            .nose: JointPoint(x: 0.5, y: 0.62, confidence: 0.95),
            .leftHip: JointPoint(x: 0.5, y: 0.54, confidence: 0.95),
            .leftKnee: JointPoint(x: 0.5, y: 0.46, confidence: 0.95),
            .leftAnkle: JointPoint(x: 0.5, y: 0.38, confidence: 0.95)
        ]
        let evaluation = PoseFramingEvaluator.evaluate(
            exercise: .squat,
            frame: PoseFrame(timestamp: 0, joints: joints, quality: .excellent, primaryAngle: 170)
        )
        XCTAssertFalse(evaluation.isReady)
        XCTAssertEqual(
            evaluation.guidance,
            "Move the phone closer while keeping head and ankles visible.".rdLocalized
        )
    }

    func testSquatFramingAcceptsAFullCenteredBody() {
        let joints = squatJoints()
        let evaluation = PoseFramingEvaluator.evaluate(
            exercise: .squat,
            frame: PoseFrame(timestamp: 0, joints: joints, quality: .excellent, primaryAngle: 170)
        )
        XCTAssertTrue(evaluation.isReady)
    }

    func testPartialSquatFramingDoesNotRequireAHead() {
        var joints = squatJoints()
        joints.removeValue(forKey: .nose)
        let evaluation = PoseFramingEvaluator.evaluate(
            exercise: .squat,
            frame: PoseFrame(timestamp: 0, joints: joints, quality: .excellent, primaryAngle: 170),
            trackingMode: .partialBody
        )
        XCTAssertTrue(evaluation.isReady)
    }

    func testSquatFramingRejectsAFullBodyAtTheEdgeOfTheFrame() {
        let shifted = squatJoints().mapValues {
            JointPoint(x: $0.x - 0.4, y: $0.y, confidence: $0.confidence)
        }
        let evaluation = PoseFramingEvaluator.evaluate(
            exercise: .squat,
            frame: PoseFrame(timestamp: 0, joints: shifted, quality: .excellent, primaryAngle: 170)
        )
        XCTAssertFalse(evaluation.isReady)
        XCTAssertEqual(
            evaluation.guidance,
            "Move right toward the center of the guide.".rdLocalized
        )
    }

    func testQualityThresholdsDistinguishExcellentUsableAndUnstable() {
        func joints(confidence: Double) -> [BodyJoint: JointPoint] {
            squatJoints().mapValues {
                JointPoint(x: $0.x, y: $0.y, confidence: confidence)
            }
        }
        XCTAssertEqual(PoseQualityEvaluator.evaluate(exercise: .squat, joints: joints(confidence: 0.8)).quality, .excellent)
        XCTAssertEqual(PoseQualityEvaluator.evaluate(exercise: .squat, joints: joints(confidence: 0.55)).quality, .usable)
        XCTAssertEqual(PoseQualityEvaluator.evaluate(exercise: .squat, joints: joints(confidence: 0.4)).quality, .unstable)
    }

    func testRaisedHandGestureRequiresAStableHoldBeforeConfirming() {
        var detector = CalibrationConfirmationGestureDetector(requiredHoldDuration: 0.45)

        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 1.0, handRaised: false)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 1.1, handRaised: true)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 1.35, handRaised: true)))
        XCTAssertTrue(detector.update(frame: gestureFrame(timestamp: 1.56, handRaised: true)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 1.7, handRaised: true)))
    }

    func testRaisedHandGestureResetsWhenTheHandIsLowered() {
        var detector = CalibrationConfirmationGestureDetector(requiredHoldDuration: 0.4)

        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 2.0, handRaised: true)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 2.25, handRaised: false)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 2.4, handRaised: true)))
        XCTAssertFalse(detector.update(frame: gestureFrame(timestamp: 2.65, handRaised: true)))
        XCTAssertTrue(detector.update(frame: gestureFrame(timestamp: 2.81, handRaised: true)))
    }

    private enum Side { case left, right }

    private func gestureFrame(timestamp: TimeInterval, handRaised: Bool) -> PoseFrame {
        PoseFrame(
            timestamp: timestamp,
            joints: [
                .leftShoulder: JointPoint(x: 0.4, y: 0.5, confidence: 0.95),
                .leftWrist: JointPoint(
                    x: 0.4,
                    y: handRaised ? 0.7 : 0.3,
                    confidence: 0.95
                )
            ],
            quality: .excellent,
            primaryAngle: nil
        )
    }

    private func frontalPushUpJoints(
        leftBent: Bool,
        rightBent: Bool
    ) -> [BodyJoint: JointPoint] {
        let confidence = 0.95
        let leftShoulder = JointPoint(x: 0.4, y: 0.65, confidence: confidence)
        let rightShoulder = JointPoint(x: 0.6, y: 0.65, confidence: confidence)
        let leftElbow = JointPoint(
            x: leftBent ? 0.4 : 0.35,
            y: 0.5,
            confidence: confidence
        )
        let rightElbow = JointPoint(
            x: rightBent ? 0.6 : 0.65,
            y: 0.5,
            confidence: confidence
        )
        let leftWrist = JointPoint(
            x: leftBent ? 0.25 : 0.3,
            y: leftBent ? 0.5 : 0.35,
            confidence: confidence
        )
        let rightWrist = JointPoint(
            x: rightBent ? 0.75 : 0.7,
            y: rightBent ? 0.5 : 0.35,
            confidence: confidence
        )
        return [
            .nose: JointPoint(x: 0.5, y: 0.82, confidence: confidence),
            .leftShoulder: leftShoulder,
            .leftElbow: leftElbow,
            .leftWrist: leftWrist,
            .rightShoulder: rightShoulder,
            .rightElbow: rightElbow,
            .rightWrist: rightWrist,
            .leftHip: JointPoint(x: 0.44, y: 0.36, confidence: confidence),
            .rightHip: JointPoint(x: 0.56, y: 0.36, confidence: confidence),
            .leftAnkle: JointPoint(x: 0.47, y: 0.08, confidence: confidence),
            .rightAnkle: JointPoint(x: 0.53, y: 0.08, confidence: confidence)
        ]
    }

    private func realisticFrontalPushUp(
        shoulderY: Double,
        hipY: Double,
        elbowsBent: Bool
    ) -> [BodyJoint: JointPoint] {
        let confidence = 0.95
        let wristY = 0.35
        let leftShoulder = JointPoint(x: 0.4, y: shoulderY, confidence: confidence)
        let rightShoulder = JointPoint(x: 0.6, y: shoulderY, confidence: confidence)
        let leftWrist = JointPoint(x: 0.3, y: wristY, confidence: confidence)
        let rightWrist = JointPoint(x: 0.7, y: wristY, confidence: confidence)
        let leftElbow = elbowsBent
            ? JointPoint(x: 0.3, y: shoulderY, confidence: confidence)
            : JointPoint(x: 0.35, y: (shoulderY + wristY) / 2, confidence: confidence)
        let rightElbow = elbowsBent
            ? JointPoint(x: 0.7, y: shoulderY, confidence: confidence)
            : JointPoint(x: 0.65, y: (shoulderY + wristY) / 2, confidence: confidence)
        return [
            .nose: JointPoint(x: 0.5, y: shoulderY + 0.08, confidence: confidence),
            .leftShoulder: leftShoulder,
            .rightShoulder: rightShoulder,
            .leftElbow: leftElbow,
            .rightElbow: rightElbow,
            .leftWrist: leftWrist,
            .rightWrist: rightWrist,
            .leftHip: JointPoint(x: 0.43, y: hipY, confidence: confidence),
            .rightHip: JointPoint(x: 0.57, y: hipY, confidence: confidence),
            .leftAnkle: JointPoint(x: 0.44, y: hipY - 0.16, confidence: confidence),
            .rightAnkle: JointPoint(x: 0.56, y: hipY - 0.16, confidence: confidence)
        ]
    }

    private func pushUpJoints(side: Side, hipOffset: Double) -> [BodyJoint: JointPoint] {
        let shoulder = JointPoint(x: 0, y: 0, confidence: 0.95)
        let elbow = JointPoint(x: 0.5, y: 0, confidence: 0.95)
        let wrist = JointPoint(x: 1, y: 0, confidence: 0.95)
        let hip = JointPoint(x: 0.5, y: hipOffset, confidence: 0.95)
        let ankle = JointPoint(x: 1, y: 0, confidence: 0.95)
        switch side {
        case .left:
            return [
                .leftShoulder: shoulder, .leftElbow: elbow, .leftWrist: wrist,
                .leftHip: hip, .leftAnkle: ankle
            ]
        case .right:
            return [
                .rightShoulder: shoulder, .rightElbow: elbow, .rightWrist: wrist,
                .rightHip: hip, .rightAnkle: ankle
            ]
        }
    }

    private func squatJoints() -> [BodyJoint: JointPoint] {
        [
            .nose: JointPoint(x: 0.5, y: 0.9, confidence: 0.95),
            .leftHip: JointPoint(x: 0.5, y: 0.7, confidence: 0.95),
            .leftKnee: JointPoint(x: 0.5, y: 0.4, confidence: 0.95),
            .leftAnkle: JointPoint(x: 0.5, y: 0.1, confidence: 0.95)
        ]
    }
}
