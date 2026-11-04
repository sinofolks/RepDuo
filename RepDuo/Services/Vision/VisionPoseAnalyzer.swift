import CoreVideo
import ImageIO
import os
import Vision

struct VisionAnalysisResult {
    let poseFrame: PoseFrame
    let personMask: CVPixelBuffer?
    /// The trainee's calibrated outline, if one has been captured.
    let silhouette: SkinnedSilhouette?
    /// Changes whenever `silhouette` is replaced or dropped.
    let silhouetteVersion: Int
    /// 0 at the trainee's calibrated top of the rep, 1 at the bottom.
    let depth: Double?

    init(
        poseFrame: PoseFrame,
        personMask: CVPixelBuffer?,
        silhouette: SkinnedSilhouette? = nil,
        silhouetteVersion: Int = 0,
        depth: Double? = nil
    ) {
        self.poseFrame = poseFrame
        self.personMask = personMask
        self.silhouette = silhouette
        self.silhouetteVersion = silhouetteVersion
        self.depth = depth
    }
}

final class VisionPoseAnalyzer {
    private let segmentationLogger = Logger(subsystem: "com.repduo.ios", category: "vision.segmentation")
    private let calibrationLogger = Logger(subsystem: "com.repduo.ios", category: "vision.calibration")
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
    private let calibrator = SilhouetteCalibrator()
    private var silhouette: SkinnedSilhouette?
    private var silhouetteVersion = 0
    private var poorFitSince: TimeInterval?
    private var needsSilhouetteValidation = false

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
            calibrator.reset()
            needsSilhouetteValidation = silhouette != nil
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
        updateSilhouette(
            imageAspect: Float(CVPixelBufferGetWidth(pixelBuffer)) / Float(max(CVPixelBufferGetHeight(pixelBuffer), 1)),
            target: target,
            joints: joints,
            mask: personMask,
            angle: measurement.angle,
            quality: quality,
            exercise: exercise,
            timestamp: timestamp
        )
        return VisionAnalysisResult(
            poseFrame: frame,
            personMask: personMask,
            silhouette: silhouette,
            silhouetteVersion: silhouetteVersion,
            depth: RepDepthProgress.value(
                angle: measurement.angle,
                referenceAngle: silhouette?.calibration.referenceAngle,
                exercise: exercise
            )
        )
    }

    /// With one person in view the cheaper whole-scene segmentation is enough.
    /// iOS 17+ can isolate the trainee in a multi-person frame. iOS 15/16 keep
    /// the background effect with whole-scene segmentation while the tracker
    /// still prevents another person from advancing the repetition count.
    private func personMask(handler: VNImageRequestHandler, target: PoseCandidate?, isolateTarget: Bool) -> CVPixelBuffer? {
        if #available(iOS 17.0, *), isolateTarget, let target {
            do {
                let instanceMaskRequest = VNGeneratePersonInstanceMaskRequest()
                try handler.perform([instanceMaskRequest])
                if let observation = instanceMaskRequest.results?.first,
                   let instance = Self.instance(containing: target, in: observation.instanceMask) {
                    return try observation.generateMask(forInstances: IndexSet(integer: instance))
                }
            } catch {
                segmentationLogger.error("Person instance mask failed: \(error.localizedDescription, privacy: .public)")
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

    /// Drops the calibrated outline, for example when the framing changes.
    func resetCalibration() {
        calibrator.reset()
        replaceSilhouette(nil)
    }

    /// Captures the trainee's outline while they hold the top of the rep, keeps
    /// it while it matches them, and recaptures when it stops fitting.
    private func updateSilhouette(
        imageAspect: Float,
        target: PoseCandidate,
        joints: [BodyJoint: JointPoint],
        mask: CVPixelBuffer?,
        angle: Double?,
        quality: PoseQuality,
        exercise: ExerciseType,
        timestamp: TimeInterval
    ) {
        if let current = silhouette, current.calibration.exercise != exercise {
            replaceSilhouette(nil)
        }
        if needsSilhouetteValidation, let current = silhouette {
            needsSilhouetteValidation = false
            // A newly acquired person keeps the outline only if they are the same size.
            let ratio = max(target.scale, current.calibration.bodyScale) / max(min(target.scale, current.calibration.bodyScale), 1e-6)
            if ratio > 1.3 { replaceSilhouette(nil) }
        }
        let configuration: RepDetectionConfiguration = exercise == .squat ? .squat : .pushUp
        let atTop = (angle ?? 0) >= configuration.topAngle - 12
        if let current = silhouette {
            if current.fit(to: joints) < 0.45 {
                let since = poorFitSince ?? timestamp
                poorFitSince = since
                if timestamp - since > 3, atTop {
                    calibrationLogger.info("Recapturing silhouette after a sustained poor fit")
                    replaceSilhouette(nil)
                }
            } else {
                poorFitSince = nil
            }
            return
        }
        guard quality.permitsCounting, atTop, let mask, let image = Self.grayImage(from: mask, maximumWidth: 160) else {
            calibrator.reset()
            return
        }
        guard let calibration = calibrator.add(mask: image, joints: joints, angle: angle, exercise: exercise, imageAspect: imageAspect) else { return }
        if let bound = SkinnedSilhouette(calibration: calibration) {
            calibrationLogger.info("Silhouette calibrated: \(bound.restPositions.count, privacy: .public) vertices")
            replaceSilhouette(bound)
        }
    }

    private func replaceSilhouette(_ next: SkinnedSilhouette?) {
        guard next != nil || silhouette != nil else { return }
        silhouette = next
        silhouetteVersion += 1
        poorFitSince = nil
        needsSilhouetteValidation = false
    }

    /// Box-downsamples an 8-bit or float person mask to at most `maximumWidth`.
    private static func grayImage(from buffer: CVPixelBuffer, maximumWidth: Int) -> GrayImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let isFloat = format == kCVPixelFormatType_OneComponent32Float
        guard isFloat || format == kCVPixelFormatType_OneComponent8, width > 0, height > 0 else { return nil }
        let factor = max(1, Int((Double(width) / Double(maximumWidth)).rounded(.up)))
        let outWidth = width / factor, outHeight = height / factor
        guard outWidth > 8, outHeight > 8 else { return nil }
        var pixels = [Float](repeating: 0, count: outWidth * outHeight)
        let area = Float(factor * factor)
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                var total: Float = 0
                for sy in 0..<factor {
                    let row = base.advanced(by: (y * factor + sy) * rowBytes)
                    for sx in 0..<factor {
                        let column = x * factor + sx
                        total += isFloat
                            ? row.load(fromByteOffset: column * 4, as: Float.self)
                            : Float(row.load(fromByteOffset: column, as: UInt8.self)) / 255
                    }
                }
                pixels[y * outWidth + x] = total / area
            }
        }
        return GrayImage(width: outWidth, height: outHeight, pixels: pixels)
    }

    /// Starts a new tracking session. The calibrated outline is kept and
    /// re-validated against whoever is acquired next.
    func reset() {
        calibrator.reset()
        poorFitSince = nil
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
