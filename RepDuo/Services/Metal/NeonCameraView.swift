import CoreImage
import CoreMedia
import MetalKit
import os
import UIKit

struct MetalRenderMetrics: Equatable {
    let gpuDurationMilliseconds: Double
}

/// Camera stage for training. The trainee's body fills with the accent color
/// as they go deeper into a rep.
///
/// Once a calibration outline exists, the body mask comes from that outline
/// bound to the live skeleton (`SkinnedSilhouette`), which is stable frame to
/// frame. The live segmentation mask takes over when the bound outline stops
/// matching, for example when a limb turns toward the camera.
final class NeonCameraView: MTKView {
    private let imageLock = NSLock()
    private let logger = Logger(subsystem: "com.repduo.ios", category: "metal.renderer")
    private var pendingFrame: CIImage?
    private var pendingMask: CIImage?
    private var previousMask: CIImage?
    private var maskTransitionStartedAt: TimeInterval?
    private var lastMaskIdentity: ObjectIdentifier?
    private var lastMaskSeenAt: TimeInterval?
    private var silhouette: SkinnedSilhouette?
    private var silhouetteChanged = false
    private var targetJoints: [BodyJoint: JointPoint] = [:]
    private var targetDepth: Double?
    private var bodySeenAt: TimeInterval?

    // Render-thread state; only touched inside `draw`.
    private var context: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var meshRenderer: SilhouetteMeshRenderer?
    private var smoothedJoints: [BodyJoint: JointPoint] = [:]
    private var depthLevel: Double = 0
    private var flash: Double = 0
    private var gold: Double = 0
    private var lastDrawAt: TimeInterval?
    private var pulseRequested = false
    private var goldRequested = false

    private let renderingColorSpace = CGColorSpaceCreateDeviceRGB()
    private let maskFadeDuration: TimeInterval = 0.28
    private let bodyTimeout: TimeInterval = 0.5
    private let compositor = BodyStageCompositor()

    /// Strength of the fill and outline, from Settings.
    var intensity: Float = 0.85
    var trackingConfidence: Float = 1
    var rendererQuality: RendererQuality = .balanced {
        didSet {
            guard rendererQuality != oldValue else { return }
            logger.info("Renderer quality changed to \(self.rendererQuality.rawValue, privacy: .public)")
        }
    }
    #if DEBUG
    var onRenderMetrics: ((MetalRenderMetrics) -> Void)?
    #endif

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        translatesAutoresizingMaskIntoConstraints = false
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        isOpaque = true
        backgroundColor = RDColor.backgroundDeep
        contentMode = .scaleAspectFill
        if let metalDevice {
            // Frames are never re-rendered, so caching intermediates only costs memory.
            context = CIContext(mtlDevice: metalDevice, options: [
                .workingFormat: CIFormat.RGBA8,
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .cacheIntermediates: false
            ])
            commandQueue = metalDevice.makeCommandQueue()
            meshRenderer = SilhouetteMeshRenderer(device: metalDevice, library: metalDevice.makeDefaultLibrary())
            if meshRenderer == nil { logger.error("Silhouette mesh pipeline is unavailable") }
        } else {
            logger.fault("No Metal device is available")
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func enqueue(pixelBuffer: CVPixelBuffer, mask: CVPixelBuffer?) {
        let now = ProcessInfo.processInfo.systemUptime
        imageLock.lock()
        pendingFrame = CIImage(cvPixelBuffer: pixelBuffer)
        if let mask {
            let identity = ObjectIdentifier(mask)
            if identity != lastMaskIdentity {
                previousMask = pendingMask
                pendingMask = CIImage(cvPixelBuffer: mask)
                maskTransitionStartedAt = now
                lastMaskIdentity = identity
            }
            lastMaskSeenAt = now
        } else if let lastMaskSeenAt, now - lastMaskSeenAt > maskFadeDuration {
            pendingMask = nil
            previousMask = nil
            maskTransitionStartedAt = nil
            lastMaskIdentity = nil
            self.lastMaskSeenAt = nil
        }
        imageLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
    }

    /// Calibrated outline to bind to the skeleton; `nil` falls back to live segmentation.
    func setSilhouette(_ silhouette: SkinnedSilhouette?) {
        imageLock.lock()
        self.silhouette = silhouette
        silhouetteChanged = true
        imageLock.unlock()
    }

    /// Latest tracked pose and rep depth (0 at the top, 1 at the bottom).
    func updateBody(joints: [BodyJoint: JointPoint], depth: Double?) {
        imageLock.lock()
        targetJoints = joints
        targetDepth = depth
        bodySeenAt = ProcessInfo.processInfo.systemUptime
        imageLock.unlock()
    }

    func clearFrame() {
        imageLock.lock()
        pendingFrame = nil
        pendingMask = nil
        previousMask = nil
        maskTransitionStartedAt = nil
        lastMaskIdentity = nil
        lastMaskSeenAt = nil
        targetJoints = [:]
        targetDepth = nil
        bodySeenAt = nil
        imageLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
    }

    /// Flashes the rim after a rep; a gold rep also washes the body in gold.
    func triggerCompletionPulse(gold: Bool = false) {
        pulseRequested = true
        if gold { goldRequested = true }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        imageLock.lock()
        let camera = pendingFrame
        let currentMask = pendingMask
        let previousMask = previousMask
        let transitionStartedAt = maskTransitionStartedAt
        let maskSeenAt = lastMaskSeenAt
        let joints = targetJoints
        let depth = targetDepth
        let bodyFresh = bodySeenAt.map { now - $0 < bodyTimeout } ?? false
        let silhouette = silhouette
        if silhouetteChanged {
            meshRenderer?.setSilhouette(silhouette)
            silhouetteChanged = false
        }
        imageLock.unlock()

        guard let camera else {
            clear(drawable: drawable, commandBuffer: commandBuffer)
            return
        }
        let extent = camera.extent
        let dt = min(0.1, max(0, now - (lastDrawAt ?? now)))
        lastDrawAt = now
        advanceAnimation(joints: bodyFresh ? joints : [:], depth: bodyFresh ? depth : nil, dt: dt)

        let liveMask = self.liveMask(current: currentMask, previous: previousMask, transitionStartedAt: transitionStartedAt, now: now, extent: extent)
        let liveFade = maskSeenAt.map { max(0, min(1, 1 - (now - $0) / maskFadeDuration)) } ?? 0
        let boundMask = self.boundMask(silhouette: silhouette, extent: extent, commandBuffer: commandBuffer)

        var bodyMask: CIImage?
        if let bound = boundMask.image {
            if let liveMask, liveFade > 0, boundMask.liveWeight > 0.01 {
                bodyMask = bound.applyingFilter("CIDissolveTransition", parameters: [
                    kCIInputTargetImageKey: liveMask,
                    kCIInputTimeKey: boundMask.liveWeight
                ]).cropped(to: extent)
            } else {
                bodyMask = bound
            }
        } else if let liveMask, liveFade > 0 {
            bodyMask = liveFade >= 0.999 ? liveMask : liveMask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: liveFade, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: liveFade, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: liveFade, w: 0)
            ])
        }

        var composite = camera
        if let bodyMask {
            composite = compositor.compose(
                camera: camera,
                bodyMask: bodyMask,
                joints: smoothedJoints,
                depth: depthLevel,
                flash: flash,
                gold: gold,
                strength: Double(min(1, intensity * trackingConfidence)),
                quality: rendererQuality
            )
        }

        let target = CGRect(origin: .zero, size: drawableSize)
        let scale = max(target.width / extent.width, target.height / extent.height)
        var rendered = composite.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        rendered = rendered.transformed(by: CGAffineTransform(
            translationX: target.midX - rendered.extent.midX,
            y: target.midY - rendered.extent.midY
        ))
        context.render(rendered, to: drawable.texture, commandBuffer: commandBuffer, bounds: target, colorSpace: renderingColorSpace)
        observeCompletion(of: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Animation

    private func advanceAnimation(joints: [BodyJoint: JointPoint], depth: Double?, dt: TimeInterval) {
        // Vision updates ~15 times a second; ease toward each sample so the
        // outline glides at display rate instead of stepping.
        let follow = 1 - exp(-dt / 0.06)
        var next: [BodyJoint: JointPoint] = [:]
        for (joint, target) in joints {
            guard let previous = smoothedJoints[joint] else {
                next[joint] = target
                continue
            }
            next[joint] = JointPoint(
                x: previous.x + (target.x - previous.x) * follow,
                y: previous.y + (target.y - previous.y) * follow,
                confidence: target.confidence
            )
        }
        smoothedJoints = next

        let previousLevel = depthLevel
        let goal = depth ?? 0
        depthLevel += (goal - depthLevel) * (1 - exp(-dt / 0.08))
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if !reduceMotion, previousLevel < 0.95, depthLevel >= 0.95 { flash = 1 }
        if pulseRequested {
            pulseRequested = false
            if !reduceMotion { flash = max(flash, 0.8) }
        }
        if goldRequested {
            goldRequested = false
            gold = reduceMotion ? 0.6 : 1
        }
        flash *= exp(-dt / 0.25)
        // Gold lingers longer than the rim flash so it reads as a moment.
        gold *= exp(-dt / 0.45)
        if gold < 0.01 { gold = 0 }
    }

    // MARK: Masks

    private func liveMask(
        current: CIImage?,
        previous: CIImage?,
        transitionStartedAt: TimeInterval?,
        now: TimeInterval,
        extent: CGRect
    ) -> CIImage? {
        guard let current else { return nil }
        var mask = current
        if let previous, previous.extent == current.extent, let transitionStartedAt {
            let progress = max(0, min(1, (now - transitionStartedAt) / 0.12))
            mask = current.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: previous,
                kCIInputTimeKey: 1 - progress
            ]).cropped(to: current.extent)
        }
        let scale = CGAffineTransform(
            scaleX: extent.width / max(mask.extent.width, 1),
            y: extent.height / max(mask.extent.height, 1)
        )
        // Close small holes at the segmentation's own resolution, then upscale once.
        let closingRadius = max(1, (2 / scale.a).rounded())
        return mask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: closingRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: closingRadius])
            .cropped(to: mask.extent)
            .clampedToExtent()
            .transformed(by: scale)
            .cropped(to: extent)
    }

    /// The calibrated outline deformed to the current pose, and how much the
    /// live mask should replace it because the bound outline no longer fits.
    private func boundMask(
        silhouette: SkinnedSilhouette?,
        extent: CGRect,
        commandBuffer: MTLCommandBuffer
    ) -> (image: CIImage?, liveWeight: Double) {
        guard let silhouette,
              let meshRenderer,
              meshRenderer.hasSilhouette,
              let positions = silhouette.deform(to: smoothedJoints),
              let texture = meshRenderer.render(positions: positions, commandBuffer: commandBuffer),
              let image = CIImage(mtlTexture: texture, options: [.colorSpace: renderingColorSpace]) else {
            return (nil, 1)
        }
        let fit = silhouette.fit(to: smoothedJoints)
        let scaled = image
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / CGFloat(texture.width),
                y: extent.height / CGFloat(texture.height)
            ))
            .cropped(to: extent)
        // Full trust above 0.8 fit, hand over to the live mask by 0.4.
        return (scaled, min(1, max(0, (0.8 - fit) / 0.4)))
    }

    private func clear(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        if let renderPass = currentRenderPassDescriptor {
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)?.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func observeCompletion(of commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { [weak self] completed in
            if let error = completed.error {
                self?.logger.error("Metal command buffer failed: \(error.localizedDescription, privacy: .public)")
            }
            #if DEBUG
            let duration = max(0, completed.gpuEndTime - completed.gpuStartTime) * 1_000
            guard duration.isFinite else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onRenderMetrics?(MetalRenderMetrics(gpuDurationMilliseconds: duration))
            }
            #endif
        }
    }
}
