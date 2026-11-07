import Foundation

struct PoseQualityEvaluation: Equatable, Sendable {
    let quality: PoseQuality
    let requiredJoints: [BodyJoint]
    let averageConfidence: Double?
}

struct PoseFramingEvaluation: Equatable, Sendable {
    let isReady: Bool
    let guidance: String
}

enum PoseFramingEvaluator {
    static func evaluate(
        exercise: ExerciseType,
        frame: PoseFrame,
        trackingMode: BodyTrackingMode = .fullBody
    ) -> PoseFramingEvaluation {
        guard frame.quality.permitsCounting else {
            return PoseFramingEvaluation(isReady: false, guidance: frame.quality.message)
        }
        let quality = PoseQualityEvaluator.evaluate(
            exercise: exercise,
            joints: frame.joints,
            trackingMode: trackingMode
        )
        let points = quality.requiredJoints.compactMap { frame.joints[$0] }
        guard points.count == quality.requiredJoints.count, !points.isEmpty else {
            return PoseFramingEvaluation(
                isReady: false,
                guidance: "Keep the required joints inside the guide.".rdLocalized
            )
        }

        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        guard minX >= 0.04, maxX <= 0.96, minY >= 0.04, maxY <= 0.96 else {
            return PoseFramingEvaluation(
                isReady: false,
                guidance: "Move toward the center so the required joints stay in frame.".rdLocalized
            )
        }

        let width = maxX - minX
        let height = maxY - minY
        let centerX = (minX + maxX) / 2
        guard centerX >= 0.28, centerX <= 0.72 else {
            return PoseFramingEvaluation(
                isReady: false,
                guidance: (centerX < 0.28 ? "Move right toward the center of the guide." : "Move left toward the center of the guide.").rdLocalized
            )
        }
        // Floor moves lie along the frame, so they are judged by the longer axis.
        let extent = exercise.isFloorMove ? max(width, height) : height
        switch (trackingMode, exercise) {
        case (.fullBody, .squat) where extent < 0.48, (.fullBody, .lunge) where extent < 0.48,
             (.fullBody, .jumpRope) where extent < 0.48:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping head and ankles visible.".rdLocalized)
        case (.fullBody, .pushUp) where extent < 0.52, (.fullBody, .jumpingJack) where extent < 0.52:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping your full body and both arms visible.".rdLocalized)
        case (.fullBody, .gluteBridge) where extent < 0.52, (.fullBody, .sitUp) where extent < 0.52:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping shoulders and ankles visible.".rdLocalized)
        case (.partialBody, .squat) where extent < 0.30, (.partialBody, .lunge) where extent < 0.30:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping hip, knee and ankle visible.".rdLocalized)
        case (.partialBody, .pushUp) where extent < 0.30, (.partialBody, .jumpingJack) where extent < 0.30:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping both arms visible.".rdLocalized)
        case (.partialBody, .jumpRope) where extent < 0.30:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping shoulders and hips visible.".rdLocalized)
        case (.partialBody, .gluteBridge) where extent < 0.30, (.partialBody, .sitUp) where extent < 0.30:
            return PoseFramingEvaluation(isReady: false, guidance: "Move the phone closer while keeping shoulder, hip and knee visible.".rdLocalized)
        default:
            return PoseFramingEvaluation(isReady: true, guidance: "Hold steady while RepDuo locks your position.".rdLocalized)
        }
    }
}

enum PoseQualityEvaluator {
    static let minimumJointConfidence = 0.35
    static let excellentConfidence = 0.72
    static let usableConfidence = 0.48

    static func evaluate(
        exercise: ExerciseType,
        joints: [BodyJoint: JointPoint],
        personCount: Int = 1,
        trackingMode: BodyTrackingMode = .fullBody
    ) -> PoseQualityEvaluation {
        guard personCount <= 1 else {
            return PoseQualityEvaluation(quality: .multiplePeople, requiredJoints: [], averageConfidence: nil)
        }
        guard personCount == 1 else {
            return PoseQualityEvaluation(quality: .missingRequiredJoints, requiredJoints: [], averageConfidence: nil)
        }

        let candidates = requiredJointCandidates(for: exercise, trackingMode: trackingMode)
        let complete = candidates.compactMap { candidate -> (joints: [BodyJoint], average: Double)? in
            let points = candidate.compactMap { joints[$0] }
            guard points.count == candidate.count,
                  points.allSatisfy({ $0.confidence >= minimumJointConfidence }) else { return nil }
            return (candidate, points.map(\.confidence).reduce(0, +) / Double(points.count))
        }
        guard let best = complete.max(by: { first, second in
            if abs(first.average - second.average) <= 0.05 {
                return first.joints.count < second.joints.count
            }
            return first.average < second.average
        }) else {
            return PoseQualityEvaluation(
                quality: .missingRequiredJoints,
                requiredJoints: candidates.first ?? [],
                averageConfidence: nil
            )
        }

        let quality: PoseQuality
        if best.average >= excellentConfidence {
            quality = .excellent
        } else if best.average >= usableConfidence {
            quality = .usable
        } else {
            quality = .unstable
        }
        return PoseQualityEvaluation(
            quality: quality,
            requiredJoints: best.joints,
            averageConfidence: best.average
        )
    }

    private static func requiredJointCandidates(
        for exercise: ExerciseType,
        trackingMode: BodyTrackingMode
    ) -> [[BodyJoint]] {
        switch (trackingMode, exercise) {
        case (.fullBody, .squat):
            return [
                [.nose, .leftHip, .leftKnee, .leftAnkle],
                [.nose, .rightHip, .rightKnee, .rightAnkle]
            ]
        case (.fullBody, .pushUp):
            let frontalUpperBody: [BodyJoint] = [
                .nose,
                .leftShoulder, .leftElbow, .leftWrist,
                .rightShoulder, .rightElbow, .rightWrist,
                .leftHip, .rightHip
            ]
            return [
                frontalUpperBody + [.leftAnkle],
                frontalUpperBody + [.rightAnkle],
                [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle],
                [.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle]
            ]
        case (.partialBody, .squat):
            return [
                [.leftHip, .leftKnee, .leftAnkle],
                [.rightHip, .rightKnee, .rightAnkle]
            ]
        case (.partialBody, .pushUp):
            return [
                [
                    .leftShoulder, .leftElbow, .leftWrist,
                    .rightShoulder, .rightElbow, .rightWrist
                ],
                [.leftShoulder, .leftElbow, .leftWrist],
                [.rightShoulder, .rightElbow, .rightWrist]
            ]
        case (.fullBody, .lunge):
            return [
                [.nose, .leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
                [.nose, .leftHip, .leftKnee, .leftAnkle],
                [.nose, .rightHip, .rightKnee, .rightAnkle]
            ]
        case (.partialBody, .lunge):
            return [
                [.leftHip, .leftKnee, .leftAnkle],
                [.rightHip, .rightKnee, .rightAnkle]
            ]
        case (.fullBody, .gluteBridge), (.fullBody, .sitUp):
            return [
                [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
                [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
            ]
        case (.partialBody, .gluteBridge), (.partialBody, .sitUp):
            return [
                [.leftShoulder, .leftHip, .leftKnee],
                [.rightShoulder, .rightHip, .rightKnee]
            ]
        case (.fullBody, .jumpingJack):
            return [[
                .nose,
                .leftShoulder, .leftWrist, .rightShoulder, .rightWrist,
                .leftHip, .rightHip, .leftAnkle, .rightAnkle
            ]]
        case (.partialBody, .jumpingJack):
            return [[.leftShoulder, .leftWrist, .rightShoulder, .rightWrist, .leftHip, .rightHip]]
        case (.fullBody, .jumpRope):
            return [[.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]]
        case (.partialBody, .jumpRope):
            return [[.leftShoulder, .rightShoulder, .leftHip, .rightHip]]
        }
    }
}

enum PoseMeasurementBuilder {
    private typealias JointTriplet = (JointPoint, JointPoint, JointPoint)
    private static let frontalShoulderSeparation = 0.08
    private static let maximumFrontalArmAngleDifference = 35.0
    private static let maximumFrontalLevelDifference = 0.12

    static func measurement(
        for exercise: ExerciseType,
        joints: [BodyJoint: JointPoint],
        trackingMode: BodyTrackingMode = .fullBody
    ) -> PoseMeasurement {
        switch exercise {
        case .squat:
            let left = triplet(.leftHip, .leftKnee, .leftAnkle, joints: joints)
            let right = triplet(.rightHip, .rightKnee, .rightAnkle, joints: joints)
            guard let selected = selectHigherConfidence(left, right) else {
                return PoseMeasurement(angle: nil, formAcceptable: false)
            }
            return PoseMeasurement(
                angle: PoseGeometry.angle(selected.0, vertex: selected.1, selected.2),
                formAcceptable: true
            )

        case .pushUp:
            return pushUpMeasurement(joints: joints, trackingMode: trackingMode)

        case .lunge:
            // Both knees bend in a lunge; the deeper one carries the rep.
            let angles = [
                triplet(.leftHip, .leftKnee, .leftAnkle, joints: joints),
                triplet(.rightHip, .rightKnee, .rightAnkle, joints: joints)
            ].compactMap { $0 }.map { PoseGeometry.angle($0.0, vertex: $0.1, $0.2) }
            return PoseMeasurement(angle: angles.min(), formAcceptable: !angles.isEmpty)

        case .gluteBridge, .sitUp:
            let left = triplet(.leftShoulder, .leftHip, .leftKnee, joints: joints)
            let right = triplet(.rightShoulder, .rightHip, .rightKnee, joints: joints)
            guard let selected = selectHigherConfidence(left, right) else {
                return PoseMeasurement(angle: nil, formAcceptable: false)
            }
            let hipAngle = PoseGeometry.angle(selected.0, vertex: selected.1, selected.2)
            guard exercise == .gluteBridge else {
                return PoseMeasurement(angle: hipAngle, formAcceptable: true)
            }
            // The bridge opens the hip from about 130° lying down to a straight line at the top.
            // Flip it so resting reads high and the lift reads low, like every other move.
            return PoseMeasurement(angle: min(180, max(0, gluteBridgeFlip - hipAngle)), formAcceptable: true)

        case .jumpingJack:
            // Arm raise is the hip–shoulder–wrist angle: near 0° at the sides, near 180° overhead.
            let arms = [
                triplet(.leftHip, .leftShoulder, .leftWrist, joints: joints),
                triplet(.rightHip, .rightShoulder, .rightWrist, joints: joints)
            ].compactMap { $0 }
            guard !arms.isEmpty else { return PoseMeasurement(angle: nil, formAcceptable: false) }
            let weights = arms.map(confidence(of:))
            let raise = zip(arms, weights).map { PoseGeometry.angle($0.0, vertex: $0.1, $0.2) * $1 }
                .reduce(0, +) / max(.ulpOfOne, weights.reduce(0, +))
            return PoseMeasurement(angle: 180 - raise, formAcceptable: true)

        case .jumpRope:
            // A skip has no joint that bends; the bounce comes from `JumpRopeMotionEstimator`,
            // which needs the frames before this one.
            return PoseMeasurement(angle: nil, formAcceptable: true)
        }
    }

    /// Hip angle that maps a 175° bridge top to 130° and a 135° rest to 170°.
    static let gluteBridgeFlip = 305.0

    private static func pushUpMeasurement(
        joints: [BodyJoint: JointPoint],
        trackingMode: BodyTrackingMode
    ) -> PoseMeasurement {
        let leftArm = triplet(.leftShoulder, .leftElbow, .leftWrist, joints: joints)
        let rightArm = triplet(.rightShoulder, .rightElbow, .rightWrist, joints: joints)

        // In a frontal setup both shoulders are separated in the image. Fuse
        // both elbow angles so one noisy arm cannot drive the repetition count.
        if let leftArm,
           let rightArm,
           abs(leftArm.0.x - rightArm.0.x) >= frontalShoulderSeparation {
            let leftAngle = PoseGeometry.angle(leftArm.0, vertex: leftArm.1, leftArm.2)
            let rightAngle = PoseGeometry.angle(rightArm.0, vertex: rightArm.1, rightArm.2)
            let leftConfidence = confidence(of: leftArm)
            let rightConfidence = confidence(of: rightArm)
            let angle = (
                leftAngle * leftConfidence + rightAngle * rightConfidence
            ) / max(.ulpOfOne, leftConfidence + rightConfidence)

            guard trackingMode == .fullBody else {
                return PoseMeasurement(angle: angle, formAcceptable: true)
            }
            guard let leftHip = joints[.leftHip],
                  let rightHip = joints[.rightHip] else {
                return PoseMeasurement(angle: angle, formAcceptable: false)
            }
            let armsAreSynchronized = abs(leftAngle - rightAngle) <= maximumFrontalArmAngleDifference
            let shouldersAreLevel = abs(leftArm.0.y - rightArm.0.y) <= maximumFrontalLevelDifference
            let hipsAreLevel = abs(leftHip.y - rightHip.y) <= maximumFrontalLevelDifference
            return PoseMeasurement(
                angle: angle,
                formAcceptable: armsAreSynchronized && shouldersAreLevel && hipsAreLevel
            )
        }

        if trackingMode == .partialBody {
            guard let selected = selectHigherConfidence(leftArm, rightArm) else {
                return PoseMeasurement(angle: nil, formAcceptable: false)
            }
            return PoseMeasurement(
                angle: PoseGeometry.angle(selected.0, vertex: selected.1, selected.2),
                formAcceptable: true
            )
        }

        // Keep the original body-line validation as a fallback for side views.
        let candidates: [(arm: JointTriplet, body: JointTriplet)] = [
            pushUpCandidate(
                shoulder: .leftShoulder,
                elbow: .leftElbow,
                wrist: .leftWrist,
                hip: .leftHip,
                ankle: .leftAnkle,
                joints: joints
            ),
            pushUpCandidate(
                shoulder: .rightShoulder,
                elbow: .rightElbow,
                wrist: .rightWrist,
                hip: .rightHip,
                ankle: .rightAnkle,
                joints: joints
            )
        ].compactMap { $0 }
        guard let selected = candidates.max(by: { confidence(of: $0.arm) < confidence(of: $1.arm) }) else {
            return PoseMeasurement(angle: nil, formAcceptable: false)
        }
        let angle = PoseGeometry.angle(selected.arm.0, vertex: selected.arm.1, selected.arm.2)
        let bodyLineError = PoseGeometry.distanceFromLine(
            selected.body.1,
            lineStart: selected.body.0,
            lineEnd: selected.body.2
        )
        return PoseMeasurement(angle: angle, formAcceptable: bodyLineError < 0.18)
    }

    private static func pushUpCandidate(
        shoulder: BodyJoint,
        elbow: BodyJoint,
        wrist: BodyJoint,
        hip: BodyJoint,
        ankle: BodyJoint,
        joints: [BodyJoint: JointPoint]
    ) -> (arm: JointTriplet, body: JointTriplet)? {
        guard let shoulderPoint = joints[shoulder],
              let elbowPoint = joints[elbow],
              let wristPoint = joints[wrist],
              let hipPoint = joints[hip],
              let anklePoint = joints[ankle] else { return nil }
        return (
            arm: (shoulderPoint, elbowPoint, wristPoint),
            body: (shoulderPoint, hipPoint, anklePoint)
        )
    }

    private static func triplet(
        _ first: BodyJoint,
        _ second: BodyJoint,
        _ third: BodyJoint,
        joints: [BodyJoint: JointPoint]
    ) -> JointTriplet? {
        guard let a = joints[first], let b = joints[second], let c = joints[third] else { return nil }
        return (a, b, c)
    }

    private static func selectHigherConfidence(_ first: JointTriplet?, _ second: JointTriplet?) -> JointTriplet? {
        switch (first, second) {
        case let (.some(a), .some(b)): return confidence(of: a) >= confidence(of: b) ? a : b
        case let (.some(value), .none), let (.none, .some(value)): return value
        case (.none, .none): return nil
        }
    }

    private static func confidence(of triplet: JointTriplet) -> Double {
        triplet.0.confidence + triplet.1.confidence + triplet.2.confidence
    }
}

/// Turns the vertical bounce of a skipping body into the shared rep signal.
/// Ground level is the lowest hip height in the last moment; lift above it is
/// divided by torso length, so the distance from the camera doesn't matter.
struct JumpRopeMotionEstimator {
    /// Signal degrees per torso length of lift: a 0.1-torso hop reads as 150°.
    static let liftScale = 300.0
    private let window: TimeInterval = 1.2
    private let maximumTrackingGap: TimeInterval = 0.8
    private let minimumConfidence = 0.35
    private var hipHeights: [(timestamp: TimeInterval, height: Double)] = []

    mutating func measurement(joints: [BodyJoint: JointPoint], timestamp: TimeInterval) -> PoseMeasurement {
        if let last = hipHeights.last, timestamp - last.timestamp > maximumTrackingGap {
            reset()
        }
        guard let hip = midpoint(.leftHip, .rightHip, in: joints),
              let shoulder = midpoint(.leftShoulder, .rightShoulder, in: joints) else {
            return PoseMeasurement(angle: nil, formAcceptable: false)
        }
        let torso = hypot(shoulder.x - hip.x, shoulder.y - hip.y)
        guard torso > 0.02 else { return PoseMeasurement(angle: nil, formAcceptable: false) }

        hipHeights.append((timestamp, hip.y))
        hipHeights.removeAll { timestamp - $0.timestamp > window }
        // Vision's y grows upward, so the ground is the lowest recent hip height.
        let ground = hipHeights.map(\.height).min() ?? hip.y
        let lift = max(0, hip.y - ground) / torso
        return PoseMeasurement(angle: max(0, 180 - lift * Self.liftScale), formAcceptable: true)
    }

    mutating func reset() {
        hipHeights.removeAll()
    }

    private func midpoint(_ first: BodyJoint, _ second: BodyJoint, in joints: [BodyJoint: JointPoint]) -> (x: Double, y: Double)? {
        let points = [joints[first], joints[second]].compactMap { $0 }.filter { $0.confidence >= minimumConfidence }
        guard !points.isEmpty else { return nil }
        return (
            points.map(\.x).reduce(0, +) / Double(points.count),
            points.map(\.y).reduce(0, +) / Double(points.count)
        )
    }
}

/// Refines the noisy 2D elbow angle used for a front-facing push-up into a
/// motion signal that also requires the torso to travel toward the hands.
/// Side views and incomplete frontal observations retain the original angle.
struct PushUpMotionEstimator {
    private struct FrontalFeatures {
        let shoulderHeightAboveHands: Double
        let hipHeightAboveHands: Double?
    }

    private let minimumConfidence = 0.35
    private let minimumShoulderSeparation = 0.08
    private let maximumTrackingGap: TimeInterval = 0.8
    private var topShoulderHeight: Double?
    private var topHipHeight: Double?
    private var baselineSampleCount = 0
    private var lastTimestamp: TimeInterval?

    mutating func refine(
        _ raw: PoseMeasurement,
        joints: [BodyJoint: JointPoint],
        trackingMode: BodyTrackingMode,
        timestamp: TimeInterval
    ) -> PoseMeasurement {
        if let lastTimestamp,
           timestamp - lastTimestamp > maximumTrackingGap {
            reset()
        }
        lastTimestamp = timestamp

        guard let rawAngle = raw.angle,
              let features = frontalFeatures(in: joints) else {
            return raw
        }

        updateTopBaseline(with: features)
        guard baselineSampleCount >= 2,
              let topShoulderHeight else {
            return raw
        }

        let shoulderDepth = normalizedDepth(
            top: topShoulderHeight,
            current: features.shoulderHeightAboveHands
        )
        let elbowDepth = clamp((155 - rawAngle) / 65)
        let hipDepth: Double?
        if let topHipHeight,
           let currentHipHeight = features.hipHeightAboveHands {
            hipDepth = normalizedDepth(top: topHipHeight, current: currentHipHeight)
        } else {
            hipDepth = nil
        }

        var combinedDepth: Double
        if trackingMode == .fullBody, let hipDepth {
            combinedDepth = shoulderDepth * 0.60 + elbowDepth * 0.25 + hipDepth * 0.15
        } else {
            combinedDepth = shoulderDepth * 0.72 + elbowDepth * 0.28
        }

        // An arm-only bend must not look like a repetition, and lowering a
        // straight plank without elbow flexion must not reach the bottom state.
        if shoulderDepth < 0.18 {
            combinedDepth = min(combinedDepth, 0.26)
        }
        if elbowDepth < 0.12 {
            combinedDepth = min(combinedDepth, 0.60)
        }

        let fusedAngle = 170 - clamp(combinedDepth) * 100
        return PoseMeasurement(
            angle: fusedAngle,
            formAcceptable: raw.formAcceptable
        )
    }

    mutating func reset() {
        topShoulderHeight = nil
        topHipHeight = nil
        baselineSampleCount = 0
        lastTimestamp = nil
    }

    private mutating func updateTopBaseline(with features: FrontalFeatures) {
        guard let currentTop = topShoulderHeight else {
            topShoulderHeight = features.shoulderHeightAboveHands
            topHipHeight = features.hipHeightAboveHands
            baselineSampleCount = 1
            return
        }

        if features.shoulderHeightAboveHands > currentTop * 1.04 {
            // A clearly higher position is a newly discovered top, not an
            // in-rep fluctuation. Require one more matching frame to trust it.
            topShoulderHeight = features.shoulderHeightAboveHands
            topHipHeight = features.hipHeightAboveHands
            baselineSampleCount = 1
        } else if features.shoulderHeightAboveHands >= currentTop * 0.92 {
            topShoulderHeight = max(currentTop, features.shoulderHeightAboveHands)
            if let hipHeight = features.hipHeightAboveHands {
                topHipHeight = max(topHipHeight ?? hipHeight, hipHeight)
            }
            baselineSampleCount = min(8, baselineSampleCount + 1)
        }
    }

    private func frontalFeatures(in joints: [BodyJoint: JointPoint]) -> FrontalFeatures? {
        guard let leftShoulder = reliable(.leftShoulder, in: joints),
              let rightShoulder = reliable(.rightShoulder, in: joints),
              let leftWrist = reliable(.leftWrist, in: joints),
              let rightWrist = reliable(.rightWrist, in: joints) else { return nil }

        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        guard shoulderWidth >= minimumShoulderSeparation else { return nil }
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let handY = (leftWrist.y + rightWrist.y) / 2
        let shoulderHeight = (shoulderY - handY) / shoulderWidth
        guard shoulderHeight.isFinite, shoulderHeight > 0 else { return nil }

        let hipHeight: Double?
        if let leftHip = reliable(.leftHip, in: joints),
           let rightHip = reliable(.rightHip, in: joints) {
            hipHeight = ((leftHip.y + rightHip.y) / 2 - handY) / shoulderWidth
        } else {
            hipHeight = nil
        }
        return FrontalFeatures(
            shoulderHeightAboveHands: shoulderHeight,
            hipHeightAboveHands: hipHeight
        )
    }

    private func reliable(
        _ joint: BodyJoint,
        in joints: [BodyJoint: JointPoint]
    ) -> JointPoint? {
        guard let point = joints[joint], point.confidence >= minimumConfidence else { return nil }
        return point
    }

    private func normalizedDepth(top: Double, current: Double) -> Double {
        clamp((top - current) / max(top * 0.58, 0.22))
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

/// Hands-free confirmation for camera calibration. A raised wrist must remain
/// above its matching shoulder long enough to avoid accidental confirmations
/// from a single noisy Vision frame.
struct CalibrationConfirmationGestureDetector {
    private let requiredHoldDuration: TimeInterval
    private let minimumVerticalSeparation: Double
    private let minimumConfidence: Double
    private let maximumTrackingGap: TimeInterval
    private var raisedSince: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var didTriggerWhileRaised = false

    init(
        requiredHoldDuration: TimeInterval = 0.45,
        minimumVerticalSeparation: Double = 0.08,
        minimumConfidence: Double = 0.35,
        maximumTrackingGap: TimeInterval = 0.35
    ) {
        self.requiredHoldDuration = max(0, requiredHoldDuration)
        self.minimumVerticalSeparation = max(0, minimumVerticalSeparation)
        self.minimumConfidence = max(0, minimumConfidence)
        self.maximumTrackingGap = max(0, maximumTrackingGap)
    }

    mutating func update(frame: PoseFrame) -> Bool {
        let timestamp = frame.timestamp
        guard timestamp.isFinite else {
            reset()
            return false
        }
        if let lastTimestamp,
           timestamp <= lastTimestamp || timestamp - lastTimestamp > maximumTrackingGap {
            raisedSince = nil
            didTriggerWhileRaised = false
        }
        lastTimestamp = timestamp

        guard isEitherHandRaised(in: frame.joints) else {
            raisedSince = nil
            didTriggerWhileRaised = false
            return false
        }
        guard !didTriggerWhileRaised else { return false }
        guard let raisedSince else {
            self.raisedSince = timestamp
            if requiredHoldDuration == 0 {
                didTriggerWhileRaised = true
                return true
            }
            return false
        }
        guard timestamp - raisedSince >= requiredHoldDuration else { return false }
        didTriggerWhileRaised = true
        return true
    }

    mutating func reset() {
        raisedSince = nil
        lastTimestamp = nil
        didTriggerWhileRaised = false
    }

    private func isEitherHandRaised(in joints: [BodyJoint: JointPoint]) -> Bool {
        isHandRaised(shoulder: .leftShoulder, wrist: .leftWrist, joints: joints)
            || isHandRaised(shoulder: .rightShoulder, wrist: .rightWrist, joints: joints)
    }

    private func isHandRaised(
        shoulder: BodyJoint,
        wrist: BodyJoint,
        joints: [BodyJoint: JointPoint]
    ) -> Bool {
        guard let shoulderPoint = joints[shoulder],
              let wristPoint = joints[wrist],
              shoulderPoint.confidence >= minimumConfidence,
              wristPoint.confidence >= minimumConfidence else { return false }
        return wristPoint.y - shoulderPoint.y >= minimumVerticalSeparation
    }
}

/// A lightweight exponential smoother. Missing joints are not synthesized, so
/// quality gating still freezes the repetition engine on occlusion.
final class PoseSmoother {
    private let alpha: Double
    private let resetInterval: TimeInterval
    private var previous: [BodyJoint: JointPoint] = [:]
    private var lastTimestamp: TimeInterval?

    init(alpha: Double = 0.42, resetInterval: TimeInterval = 0.6) {
        self.alpha = min(1, max(0, alpha))
        self.resetInterval = max(0, resetInterval)
    }

    func smooth(_ joints: [BodyJoint: JointPoint], at timestamp: TimeInterval) -> [BodyJoint: JointPoint] {
        guard let lastTimestamp,
              timestamp >= lastTimestamp,
              timestamp - lastTimestamp <= resetInterval else {
            previous = joints
            self.lastTimestamp = timestamp
            return joints
        }

        let smoothed = joints.mapValues { current in current }.reduce(into: [BodyJoint: JointPoint]()) { result, entry in
            let (joint, current) = entry
            guard let prior = previous[joint] else {
                result[joint] = current
                return
            }
            result[joint] = JointPoint(
                x: prior.x + (current.x - prior.x) * alpha,
                y: prior.y + (current.y - prior.y) * alpha,
                confidence: current.confidence
            )
        }
        previous = smoothed
        self.lastTimestamp = timestamp
        return smoothed
    }

    func reset() {
        previous.removeAll(keepingCapacity: true)
        lastTimestamp = nil
    }
}
