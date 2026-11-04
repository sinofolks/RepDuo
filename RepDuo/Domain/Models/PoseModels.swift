import Foundation

enum BodyJoint: String, CaseIterable, Sendable {
    case nose
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

struct PoseMeasurement: Equatable, Sendable {
    let angle: Double?
    let formAcceptable: Bool
}

struct JointPoint: Equatable, Sendable {
    let x: Double
    let y: Double
    let confidence: Double
}

struct PoseFrame: Equatable, Sendable {
    let timestamp: TimeInterval
    let joints: [BodyJoint: JointPoint]
    let quality: PoseQuality
    let primaryAngle: Double?
    let isFormAcceptable: Bool
    /// Other people in view who are being ignored while the trainee is tracked.
    let bystanderCount: Int

    init(
        timestamp: TimeInterval,
        joints: [BodyJoint: JointPoint] = [:],
        quality: PoseQuality,
        primaryAngle: Double?,
        isFormAcceptable: Bool = true,
        bystanderCount: Int = 0
    ) {
        self.timestamp = timestamp
        self.joints = joints
        self.quality = quality
        self.primaryAngle = primaryAngle
        self.isFormAcceptable = isFormAcceptable
        self.bystanderCount = bystanderCount
    }
}

enum PoseGeometry {
    static func angle(_ first: JointPoint, vertex: JointPoint, _ third: JointPoint) -> Double {
        let a = (x: first.x - vertex.x, y: first.y - vertex.y)
        let b = (x: third.x - vertex.x, y: third.y - vertex.y)
        let magnitude = hypot(a.x, a.y) * hypot(b.x, b.y)
        guard magnitude > .ulpOfOne else { return 0 }
        let cosine = max(-1, min(1, (a.x * b.x + a.y * b.y) / magnitude))
        return acos(cosine) * 180 / .pi
    }

    static func distanceFromLine(_ point: JointPoint, lineStart: JointPoint, lineEnd: JointPoint) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let denominator = hypot(dx, dy)
        guard denominator > .ulpOfOne else { return .infinity }
        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / denominator
    }
}

/// Maps Vision's normalized, bottom-left coordinate space into an aspect-fill
/// viewport whose origin is at the top-left. Keeping this transform in Domain
/// makes camera, pose-overlay, and snapshot behavior independently testable.
enum PoseCoordinateTransform {
    static func aspectFill(
        _ point: JointPoint,
        imageWidth: Double,
        imageHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        mirrored: Bool
    ) -> JointPoint {
        guard imageWidth > 0, imageHeight > 0, viewportWidth > 0, viewportHeight > 0 else {
            return point
        }

        let normalizedX = mirrored ? 1 - point.x : point.x
        let imageX = normalizedX * imageWidth
        let imageY = (1 - point.y) * imageHeight
        let scale = max(viewportWidth / imageWidth, viewportHeight / imageHeight)
        let offsetX = (viewportWidth - imageWidth * scale) / 2
        let offsetY = (viewportHeight - imageHeight * scale) / 2

        return JointPoint(
            x: imageX * scale + offsetX,
            y: imageY * scale + offsetY,
            confidence: point.confidence
        )
    }
}
