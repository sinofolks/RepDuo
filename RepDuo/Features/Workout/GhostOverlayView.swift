import UIKit

/// The ghost: a translucent stick body replaying an earlier set over the camera.
/// Drawn in the same camera space as the live body, so when the trainee stands
/// where they stood last time the ghost moves over them and drifts ahead or behind.
final class GhostOverlayView: UIView {
    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]

    private let bodyLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        bodyLayer.fillColor = RDColor.warmWhite.withAlphaComponent(0.32).cgColor
        // Filled limb outlines rather than a stroke, so overlapping limbs don't double up.
        bodyLayer.strokeColor = nil
        bodyLayer.shadowColor = RDColor.warmWhite.cgColor
        bodyLayer.shadowRadius = 10
        bodyLayer.shadowOpacity = 0.5
        bodyLayer.shadowOffset = .zero
        layer.addSublayer(bodyLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        bodyLayer.frame = bounds
    }

    /// Draws `joints`, or hides the ghost when there is no pose to show.
    func render(_ joints: [BodyJoint: JointPoint]?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let joints, bounds.width > 0 else {
            bodyLayer.path = nil
            return
        }
        let points = joints.mapValues { joint -> CGPoint in
            let mapped = PoseCoordinateTransform.aspectFill(
                joint,
                imageWidth: 720,
                imageHeight: 1280,
                viewportWidth: Double(bounds.width),
                viewportHeight: Double(bounds.height),
                mirrored: false
            )
            return CGPoint(x: mapped.x, y: mapped.y)
        }
        let path = UIBezierPath()
        for (start, end) in Self.bones {
            guard let a = points[start], let b = points[end] else { continue }
            path.move(to: a)
            path.addLine(to: b)
        }
        // Limbs scale with the body, so a ghost far from the camera stays in proportion.
        // Torso length works side-on too, where the shoulders sit on top of each other.
        let torsoLengths = [(BodyJoint.leftShoulder, BodyJoint.leftHip), (.rightShoulder, .rightHip)]
            .compactMap { pair -> CGFloat? in
                guard let a = points[pair.0], let b = points[pair.1] else { return nil }
                return hypot(a.x - b.x, a.y - b.y)
            }
        let limbWidth = max(6, min(20, (torsoLengths.max() ?? 160) * 0.08))
        let stroked = UIBezierPath(cgPath: path.cgPath.copy(
            strokingWithWidth: limbWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 1
        ))
        if let nose = points[.nose] {
            let radius = limbWidth * 1.4
            stroked.append(UIBezierPath(ovalIn: CGRect(x: nose.x - radius, y: nose.y - radius, width: radius * 2, height: radius * 2)))
        }
        bodyLayer.path = stroked.cgPath
    }
}
