import CoreImage

/// Builds the training stage from a camera frame and a body mask: the camera
/// image stays as it is, a soft accent fill rises along the body with rep
/// depth, and a thin rim brightens at the bottom of each rep.
struct BodyStageCompositor {
    /// RDColor.neonGreen.
    var fillColor = (red: 0.78, green: 1.0, blue: 0.12)
    /// RDColor.reward.
    var goldColor = (red: 1.0, green: 0.84, blue: 0.04)

    /// - Parameters:
    ///   - joints: Vision-normalized joints of the trainee.
    ///   - depth: 0 at the top of the rep, 1 at the bottom.
    ///   - flash: 0...1 rim boost after reaching the bottom.
    ///   - gold: 0...1 gold wash over the whole body after a gold rep.
    ///   - strength: overall effect strength from Settings and tracking confidence.
    func compose(
        camera: CIImage,
        bodyMask: CIImage,
        joints: [BodyJoint: JointPoint],
        depth: Double,
        flash: Double,
        gold: Double = 0,
        strength: Double,
        quality: RendererQuality
    ) -> CIImage {
        let extent = camera.extent
        var stage = camera.cropped(to: extent)

        if depth > 0.01, let gradient = depthGradient(extent: extent, joints: joints, depth: depth, alpha: 0.6 * strength) {
            let fill = gradient.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: bodyMask
            ]).cropped(to: extent)
            stage = fill.composited(over: stage)
        }

        if gold > 0.01 {
            let alpha = 0.5 * gold * strength
            let wash = CIImage(color: CIColor(
                red: goldColor.red * alpha,
                green: goldColor.green * alpha,
                blue: goldColor.blue * alpha,
                alpha: alpha
            )).cropped(to: extent).applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: bodyMask
            ]).cropped(to: extent)
            stage = wash.composited(over: stage)
        }

        if quality != .thermalSafe {
            let rimAlpha = (0.18 + 0.6 * max(flash, gold)) * strength
            // White rim, shifting to gold during a gold rep.
            let rimBlue = 1 - gold * (1 - goldColor.blue)
            let rimGreen = 1 - gold * (1 - goldColor.green)
            let rim = bodyMask
                .applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: quality == .lowPower ? 1.0 : 1.5])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: rimAlpha, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 1, y: rimGreen, z: rimBlue, w: 0)
                ])
                .applyingFilter("CIPremultiply")
                .cropped(to: extent)
            stage = rim.composited(over: stage)
        }
        return stage
    }

    /// Soft-edged fill along the body's own axis, feet to head: vertical in a
    /// squat, nearly horizontal in a push-up.
    private func depthGradient(extent: CGRect, joints: [BodyJoint: JointPoint], depth: Double, alpha: Double) -> CIImage? {
        func point(_ joint: BodyJoint) -> CGPoint? {
            joints[joint].map { CGPoint(x: $0.x * extent.width, y: $0.y * extent.height) }
        }
        func mid(_ a: BodyJoint, _ b: BodyJoint) -> CGPoint? {
            switch (point(a), point(b)) {
            case let (a?, b?): return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            case let (a?, nil), let (nil, a?): return a
            default: return nil
            }
        }
        guard let feet = mid(.leftAnkle, .rightAnkle) ?? mid(.leftKnee, .rightKnee),
              let head = point(.nose) ?? point(.neck) else { return nil }
        let axis = CGVector(dx: head.x - feet.x, dy: head.y - feet.y)
        guard hypot(axis.dx, axis.dy) > 1 else { return nil }
        // Extend past the feet and the top of the head so 0 and 1 cover the whole outline.
        let start = CGPoint(x: feet.x - axis.dx * 0.05, y: feet.y - axis.dy * 0.05)
        let span = CGVector(dx: axis.dx * 1.2, dy: axis.dy * 1.2)
        let band = 0.06
        let lower = max(0, depth - band), upper = min(1.05, depth + band)
        let color = CIColor(red: fillColor.red, green: fillColor.green, blue: fillColor.blue, alpha: alpha)
        let clear = CIColor(red: fillColor.red, green: fillColor.green, blue: fillColor.blue, alpha: 0)
        return CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: start.x + span.dx * lower, y: start.y + span.dy * lower),
            "inputPoint1": CIVector(x: start.x + span.dx * upper, y: start.y + span.dy * upper),
            "inputColor0": color,
            "inputColor1": clear
        ])?.outputImage?.cropped(to: extent)
    }
}
