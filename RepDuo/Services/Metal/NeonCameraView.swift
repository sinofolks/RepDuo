import CoreImage
import CoreMedia
import MetalKit
import MetalPerformanceShaders
import os
import UIKit

struct MetalRenderMetrics: Equatable {
    let gpuDurationMilliseconds: Double
}

final class NeonCameraView: MTKView {
    private struct GlowTextures {
        let width: Int
        let height: Int
        let source: MTLTexture
        let main: MTLTexture
        let outer: MTLTexture
    }

    private let imageLock = NSLock()
    private let logger = Logger(subsystem: "com.repduo.ios", category: "metal.renderer")
    private var pendingFrame: CIImage?
    private var pendingMask: CIImage?
    private var previousMask: CIImage?
    private var maskTransitionStartedAt: TimeInterval?
    private var lastMaskIdentity: ObjectIdentifier?
    private var lastMaskSeenAt: TimeInterval?
    private var context: CIContext?
    private var commandQueue: MTLCommandQueue?
    private var glowTextures: GlowTextures?
    private var balancedBlur: MPSImageGaussianBlur?
    private var lowPowerBlur: MPSImageGaussianBlur?
    private var outerBlur: MPSImageGaussianBlur?
    private let renderingColorSpace = CGColorSpaceCreateDeviceRGB()
    private let maskFadeDuration: TimeInterval = 0.28
    /// Glows are blurred at this fraction of camera resolution; a wide blur
    /// removes the detail a full-resolution pass would preserve.
    private let glowScale: CGFloat = 0.5
    private var pulseEndsAt: TimeInterval = 0

    var intensity: Float = 0.85
    var trackingConfidence: Float = 1
    var replacesBackground = true
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
        backgroundColor = RDColor.camera
        contentMode = .scaleAspectFill
        if let metalDevice {
            // The glow is already blurred in 8-bit textures, so an 8-bit, gamma-space
            // pipeline halves bandwidth without visible banding. Frames are never
            // re-rendered, so caching intermediates only costs memory.
            context = CIContext(mtlDevice: metalDevice, options: [
                .workingFormat: CIFormat.RGBA8,
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .cacheIntermediates: false
            ])
            commandQueue = metalDevice.makeCommandQueue()
            // Sigmas are in glow-texture pixels, which are `glowScale` of camera pixels.
            balancedBlur = MPSImageGaussianBlur(device: metalDevice, sigma: Float(12 * glowScale))
            lowPowerBlur = MPSImageGaussianBlur(device: metalDevice, sigma: Float(7 * glowScale))
            outerBlur = MPSImageGaussianBlur(device: metalDevice, sigma: Float(24 * glowScale))
            balancedBlur?.edgeMode = .clamp
            lowPowerBlur?.edgeMode = .clamp
            outerBlur?.edgeMode = .clamp
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
                let current = CIImage(cvPixelBuffer: mask)
                previousMask = pendingMask
                pendingMask = current
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

    func clearFrame() {
        imageLock.lock()
        pendingFrame = nil
        pendingMask = nil
        previousMask = nil
        maskTransitionStartedAt = nil
        lastMaskIdentity = nil
        lastMaskSeenAt = nil
        imageLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
    }

    func triggerCompletionPulse() {
        pulseEndsAt = ProcessInfo.processInfo.systemUptime + 0.2
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        imageLock.lock()
        let camera = pendingFrame
        let currentMask = pendingMask
        let previousMask = previousMask
        let transitionStartedAt = maskTransitionStartedAt
        let maskSeenAt = lastMaskSeenAt
        imageLock.unlock()
        guard let camera else {
            if let renderPass = currentRenderPassDescriptor {
                renderPass.colorAttachments[0].loadAction = .clear
                renderPass.colorAttachments[0].clearColor = MTLClearColor(
                    red: 0.063,
                    green: 0.075,
                    blue: 0.09,
                    alpha: 1
                )
                commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)?.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let stageBackground = CIImage(
            color: CIColor(red: 0.063, green: 0.075, blue: 0.09, alpha: 1)
        ).cropped(to: camera.extent)
        var composite = replacesBackground ? stageBackground : camera
        let now = ProcessInfo.processInfo.systemUptime
        let fade = maskSeenAt.map { max(0, min(1, 1 - (now - $0) / maskFadeDuration)) } ?? 0
        let mask: CIImage?
        if let currentMask,
           let previousMask,
           previousMask.extent == currentMask.extent,
           let transitionStartedAt {
            let progress = max(0, min(1, (now - transitionStartedAt) / 0.12))
            mask = currentMask.applyingFilter(
                "CIDissolveTransition",
                parameters: [
                    kCIInputTargetImageKey: previousMask,
                    kCIInputTimeKey: 1 - progress
                ]
            ).cropped(to: currentMask.extent)
        } else {
            mask = currentMask
        }
        if let mask, fade > 0 {
            let maskScale = CGAffineTransform(
                scaleX: camera.extent.width / max(mask.extent.width, 1),
                y: camera.extent.height / max(mask.extent.height, 1)
            )
            // Close small holes at the segmentation's own resolution, which is a
            // fraction of the camera's, then upscale once. Bilinear upscaling
            // also gives the blend mask its soft edge.
            let closingRadius = max(1, (2 / maskScale.a).rounded())
            let fullMask = mask
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: closingRadius])
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: closingRadius])
                .cropped(to: mask.extent)
                .clampedToExtent()
                .transformed(by: maskScale)
                .cropped(to: camera.extent)
            let softenedPersonMask = fullMask
            let isolatedPerson = camera.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: stageBackground,
                    kCIInputMaskImageKey: softenedPersonMask
                ]
            ).cropped(to: camera.extent)
            let cameraBase: CIImage
            if replacesBackground {
                // If segmentation momentarily disappears, fade the isolated
                // person into the black stage without ever revealing the room.
                cameraBase = fade >= 0.999
                    ? isolatedPerson
                    : isolatedPerson.applyingFilter(
                        "CIDissolveTransition",
                        parameters: [
                            kCIInputTargetImageKey: stageBackground,
                            kCIInputTimeKey: 1 - fade
                        ]
                    ).cropped(to: camera.extent)
            } else {
                cameraBase = camera
            }
            let edge = fullMask
                .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 8.0])
                .cropped(to: camera.extent)
            let clear = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            let pulse: Float = now < pulseEndsAt && !UIAccessibility.isReduceMotionEnabled ? 1.3 : 1
            let effectiveIntensity = CGFloat(min(1, intensity * trackingConfidence * Float(fade) * pulse))
            let green = CIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: effectiveIntensity)
            let bright = CIColor(red: 0.55, green: 0.93, blue: 0.62, alpha: effectiveIntensity)
            let colorized = edge
                .applyingFilter("CIFalseColor", parameters: ["inputColor0": clear, "inputColor1": green])
            let inner = edge.applyingFilter(
                "CIFalseColor",
                parameters: ["inputColor0": clear, "inputColor1": bright]
            )
            switch rendererQuality {
            case .high:
                let glows = makeMPSGlows(
                    colorized: colorized,
                    extent: camera.extent,
                    context: context,
                    commandBuffer: commandBuffer,
                    includeOuter: true
                )
                let mainGlow = glows?.main ?? fallbackGlow(colorized, radius: 12, extent: camera.extent)
                let outerGlow = glows?.outer ?? fallbackGlow(colorized, radius: 24, extent: camera.extent)
                composite = inner.composited(
                    over: mainGlow.composited(over: outerGlow.composited(over: cameraBase))
                )
            case .balanced, .lowPower:
                let radius: Float = rendererQuality == .lowPower ? 7 : 12
                let mainGlow = makeMPSGlows(
                    colorized: colorized,
                    extent: camera.extent,
                    context: context,
                    commandBuffer: commandBuffer,
                    includeOuter: false
                )?.main ?? fallbackGlow(colorized, radius: radius, extent: camera.extent)
                composite = inner.composited(over: mainGlow.composited(over: cameraBase))
            case .thermalSafe:
                composite = inner.composited(over: cameraBase)
            }
        }

        let target = CGRect(origin: .zero, size: drawableSize)
        let scale = max(target.width / composite.extent.width, target.height / composite.extent.height)
        var rendered = composite.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        rendered = rendered.transformed(by: CGAffineTransform(
            translationX: target.midX - rendered.extent.midX,
            y: target.midY - rendered.extent.midY
        ))
        context.render(
            rendered,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: target,
            colorSpace: renderingColorSpace
        )
        observeCompletion(of: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeMPSGlows(
        colorized: CIImage,
        extent: CGRect,
        context: CIContext,
        commandBuffer: MTLCommandBuffer,
        includeOuter: Bool
    ) -> (main: CIImage, outer: CIImage?)? {
        let downscale = CGAffineTransform(scaleX: glowScale, y: glowScale)
        let glowExtent = extent.applying(downscale)
        let width = Int(glowExtent.width.rounded(.up))
        let height = Int(glowExtent.height.rounded(.up))
        guard let textures = textures(width: width, height: height) else { return nil }
        context.render(
            colorized.transformed(by: downscale),
            to: textures.source,
            commandBuffer: commandBuffer,
            bounds: CGRect(x: glowExtent.minX, y: glowExtent.minY, width: CGFloat(width), height: CGFloat(height)),
            colorSpace: renderingColorSpace
        )
        let blur = rendererQuality == .lowPower ? lowPowerBlur : balancedBlur
        guard let blur else { return nil }
        blur.encode(
            commandBuffer: commandBuffer,
            sourceTexture: textures.source,
            destinationTexture: textures.main
        )
        if includeOuter {
            outerBlur?.encode(
                commandBuffer: commandBuffer,
                sourceTexture: textures.source,
                destinationTexture: textures.outer
            )
        }

        let options: [CIImageOption: Any] = [.colorSpace: renderingColorSpace]
        // Textures start at the origin; move them back to the extent at camera scale.
        let upscale = CGAffineTransform(scaleX: 1 / glowScale, y: 1 / glowScale)
            .translatedBy(x: glowExtent.minX, y: glowExtent.minY)
        func restore(_ texture: MTLTexture) -> CIImage? {
            CIImage(mtlTexture: texture, options: options)?.transformed(by: upscale).cropped(to: extent)
        }
        guard let main = restore(textures.main) else { return nil }
        return (main, includeOuter ? restore(textures.outer) : nil)
    }

    private func textures(width: Int, height: Int) -> GlowTextures? {
        if let glowTextures,
           glowTextures.width == width,
           glowTextures.height == height {
            return glowTextures
        }
        guard let device, width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let source = device.makeTexture(descriptor: descriptor),
              let main = device.makeTexture(descriptor: descriptor),
              let outer = device.makeTexture(descriptor: descriptor) else { return nil }
        let textures = GlowTextures(width: width, height: height, source: source, main: main, outer: outer)
        glowTextures = textures
        return textures
    }

    private func fallbackGlow(_ image: CIImage, radius: Float, extent: CGRect) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
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
