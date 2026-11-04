import Metal
import simd

/// Draws a `SkinnedSilhouette` into a mask texture on the GPU: the deformed
/// mesh samples the calibrated outline, so the mask moves with the skeleton
/// while keeping the calibration's clean edge.
final class SilhouetteMeshRenderer {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private var maskTexture: MTLTexture?
    private var labelTexture: MTLTexture?
    private var partBuffer: MTLBuffer?
    private var outputTexture: MTLTexture?
    private var uvBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var positionBuffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private var indexCount = 0
    private var vertexCount = 0

    /// Output is drawn at this multiple of the calibration mask's size.
    private let outputScale = 2

    init?(device: MTLDevice, library: MTLLibrary?) {
        guard let library,
              let vertex = library.makeFunction(name: "silhouette_vertex"),
              let fragment = library.makeFunction(name: "silhouette_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .rgba8Unorm
        // Where limbs overlap, keep the stronger coverage instead of summing it.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .max
        attachment.alphaBlendOperation = .max
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.pipeline = pipeline
    }

    var hasSilhouette: Bool { maskTexture != nil }

    func setSilhouette(_ silhouette: SkinnedSilhouette?) {
        guard let silhouette else {
            maskTexture = nil
            labelTexture = nil
            outputTexture = nil
            return
        }
        let mask = silhouette.calibration.mask
        let bytes = mask.pixels.map { UInt8(max(0, min(1, $0)) * 255) }
        let maskDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: mask.width,
            height: mask.height,
            mipmapped: false
        )
        maskDescriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: maskDescriptor)
        bytes.withUnsafeBytes {
            texture?.replace(
                region: MTLRegionMake2D(0, 0, mask.width, mask.height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: mask.width
            )
        }
        let labelDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint,
            width: mask.width,
            height: mask.height,
            mipmapped: false
        )
        labelDescriptor.usage = .shaderRead
        let labels = device.makeTexture(descriptor: labelDescriptor)
        silhouette.partLabels.withUnsafeBytes {
            labels?.replace(
                region: MTLRegionMake2D(0, 0, mask.width, mask.height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: mask.width
            )
        }
        labelTexture = labels
        partBuffer = silhouette.vertexParts.map { Float($0.rawValue) }.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)
        }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: mask.width * outputScale,
            height: mask.height * outputScale,
            mipmapped: false
        )
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .private
        maskTexture = texture
        outputTexture = device.makeTexture(descriptor: outputDescriptor)
        uvBuffer = silhouette.textureCoordinates.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)
        }
        indexBuffer = silhouette.triangleIndices.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)
        }
        indexCount = silhouette.triangleIndices.count
        vertexCount = silhouette.restPositions.count
        let length = MemoryLayout<SIMD2<Float>>.stride * vertexCount
        // Three position buffers so the CPU never writes one the GPU is still reading.
        positionBuffers = (0..<3).compactMap { _ in device.makeBuffer(length: length, options: .storageModeShared) }
    }

    /// Encodes the deformed silhouette and returns the texture it lands in.
    func render(positions: [SIMD2<Float>], commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let maskTexture, let labelTexture, let outputTexture, let uvBuffer, let partBuffer, let indexBuffer,
              positions.count == vertexCount, !positionBuffers.isEmpty else { return nil }
        bufferIndex = (bufferIndex + 1) % positionBuffers.count
        let positionBuffer = positionBuffers[bufferIndex]
        positions.withUnsafeBytes {
            positionBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count)
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = outputTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(partBuffer, offset: 0, index: 2)
        encoder.setFragmentTexture(maskTexture, index: 0)
        encoder.setFragmentTexture(labelTexture, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.endEncoding()
        return outputTexture
    }
}
