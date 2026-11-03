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
    private var pushUpMotionEstimator = PushUpMotionEstimator()
    private var previousMaskAvailability: Bool?
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    func analyze(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        exercise: ExerciseType,
        trackingMode: BodyTrackingMode = .fullBody
    ) throws -> VisionAnalysisResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([poseRequest, segmentationRequest])
        let observations = poseRequest.results ?? []
        let personMask = observations.isEmpty ? nil : segmentationRequest.results?.first?.pixelBuffer
        let maskAvailable = personMask != nil
        if previousMaskAvailability != maskAvailable {
            segmentationLogger.info("Person segmentation availability changed: \(maskAvailable, privacy: .public)")
            previousMaskAvailability = maskAvailable
        }
        if observations.count > 1 {
            return VisionAnalysisResult(
                poseFrame: PoseFrame(timestamp: timestamp, quality: .multiplePeople, primaryAngle: nil),
                personMask: personMask
            )
        }
        guard let observation = observations.first else {
            return VisionAnalysisResult(
                poseFrame: PoseFrame(timestamp: timestamp, quality: .missingRequiredJoints, primaryAngle: nil),
                personMask: nil
            )
        }

        let recognized = try observation.recognizedPoints(.all)
        let rawJoints = mapRecognizedPoints(recognized)
        let joints = smoother.smooth(rawJoints, at: timestamp)
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
            isFormAcceptable: measurement.formAcceptable
        )
        return VisionAnalysisResult(poseFrame: frame, personMask: personMask)
    }

    func reset() {
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
