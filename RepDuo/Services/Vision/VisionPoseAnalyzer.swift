import CoreVideo
import ImageIO
import os
import Vision

struct VisionAnalysisResult {
    let poseFrame: PoseFrame
    let personMask: CVPixelBuffer?
}

final class VisionPoseAnalyzer {
    private let segmentationLogger = Logger(subsystem: "com.repduo.ios", category: "vision.segmentation")
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let smoother = PoseSmoother()
    private let tracker = TargetPersonTracker()
    private var currentTrackID = 0
    private var pushUpMotionEstimator = PushUpMotionEstimator()
    private var previousMaskAvailability: Bool?
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let instanceMaskRequest = VNGeneratePersonInstanceMaskRequest()

    func analyze(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        exercise: ExerciseType,
        trackingMode: BodyTrackingMode = .fullBody
    ) throws -> VisionAnalysisResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([poseRequest])
        let observations = poseRequest.results ?? []
        let candidates = try observations.compactMap { observation in
            PoseCandidate(joints: mapRecognizedPoints(try observation.recognizedPoints(.all)))
        }
        let tracking = tracker.update(candidates: candidates, at: timestamp)
        if tracking.trackID != currentTrackID {
            // A different person was acquired; don't blend their joints with the last one's.
            currentTrackID = tracking.trackID
            smoother.reset()
            pushUpMotionEstimator.reset()
        }
        let target = tracking.targetIndex.map { candidates[$0] }
        let personMask = observations.isEmpty
            ? nil
            : self.personMask(handler: handler, target: target, isolateTarget: observations.count > 1)
        let maskAvailable = personMask != nil
        if previousMaskAvailability != maskAvailable {
            segmentationLogger.info("Person segmentation availability changed: \(maskAvailable, privacy: .public)")
            previousMaskAvailability = maskAvailable
        }

        guard let target else {
            let quality: PoseQuality = tracking.status == .ambiguous ? .multiplePeople : .missingRequiredJoints
            return VisionAnalysisResult(
                poseFrame: PoseFrame(
                    timestamp: timestamp,
                    quality: quality,
                    primaryAngle: nil,
                    bystanderCount: tracking.bystanderCount
                ),
                personMask: personMask
            )
        }

        let joints = smoother.smooth(target.joints, at: timestamp)
        let quality = PoseQualityEvaluator.evaluate(
            exercise: exercise,
            joints: joints,
            trackingMode: trackingMode
        ).quality
        let rawMeasurement = PoseMeasurementBuilder.measurement(
            for: exercise,
            joints: joints,
            trackingMode: trackingMode
        )
        let measurement: PoseMeasurement
        if exercise == .pushUp {
            measurement = pushUpMotionEstimator.refine(
                rawMeasurement,
                joints: joints,
                trackingMode: trackingMode,
                timestamp: timestamp
            )
        } else {
            measurement = rawMeasurement
        }
        let frame = PoseFrame(
            timestamp: timestamp,
            joints: joints,
            quality: quality,
            primaryAngle: measurement.angle,
            isFormAcceptable: measurement.formAcceptable,
            bystanderCount: tracking.bystanderCount
        )
        return VisionAnalysisResult(poseFrame: frame, personMask: personMask)
    }

    /// With one person in view the cheaper whole-scene segmentation is enough.
    /// With several, per-instance masks keep the neon glow on the trainee only.
    private func personMask(handler: VNImageRequestHandler, target: PoseCandidate?, isolateTarget: Bool) -> CVPixelBuffer? {
        if isolateTarget {
            guard let target else { return nil }
            do {
                try handler.perform([instanceMaskRequest])
                guard let observation = instanceMaskRequest.results?.first,
                      let instance = Self.instance(containing: target, in: observation.instanceMask) else { return nil }
                return try observation.generateMask(forInstances: IndexSet(integer: instance))
            } catch {
                segmentationLogger.error("Person instance mask failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        do {
            try handler.perform([segmentationRequest])
            return segmentationRequest.results?.first?.pixelBuffer
        } catch {
            segmentationLogger.error("Person segmentation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Picks the instance label found most often under the target's torso and limb joints.
    private static func instance(containing target: PoseCandidate, in labels: CVPixelBuffer) -> Int? {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let width = CVPixelBufferGetWidth(labels)
        let height = CVPixelBufferGetHeight(labels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(labels)
        let samples: [BodyJoint] = [
            .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip,
            .leftElbow, .rightElbow, .leftKnee, .rightKnee
        ]
        var votes: [Int: Int] = [:]
        for joint in samples {
            guard let point = target.joints[joint] else { continue }
            // Vision points are bottom-left normalized; buffer rows start at the top.
            let x = min(width - 1, max(0, Int(point.x * Double(width))))
            let y = min(height - 1, max(0, Int((1 - point.y) * Double(height))))
            let label = Int(base.load(fromByteOffset: y * bytesPerRow + x, as: UInt8.self))
            if label != 0 { votes[label, default: 0] += 1 }
        }
        return votes.max { $0.value < $1.value }?.key
    }

    func reset() {
        tracker.reset()
        smoother.reset()
        pushUpMotionEstimator.reset()
        previousMaskAvailability = nil
    }

    private func mapRecognizedPoints(
        _ recognized: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> [BodyJoint: JointPoint] {
        let pairs: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip),
            (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
        ]
        return Dictionary(uniqueKeysWithValues: pairs.compactMap { joint, visionName in
            guard let point = recognized[visionName], point.confidence > 0.15 else { return nil }
            return (joint, JointPoint(x: point.location.x, y: point.location.y, confidence: Double(point.confidence)))
        })
    }

}
