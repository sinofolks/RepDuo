import Foundation

enum PipelineThermalState: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

struct PipelinePerformancePolicy: Equatable, Sendable {
    let rendererQuality: RendererQuality
    let analysisStride: Int

    static func policy(for thermalState: PipelineThermalState) -> PipelinePerformancePolicy {
        switch thermalState {
        case .nominal:
            return PipelinePerformancePolicy(rendererQuality: .balanced, analysisStride: 2)
        case .fair:
            return PipelinePerformancePolicy(rendererQuality: .lowPower, analysisStride: 3)
        case .serious, .critical:
            return PipelinePerformancePolicy(rendererQuality: .thermalSafe, analysisStride: 5)
        case .unknown:
            return PipelinePerformancePolicy(rendererQuality: .lowPower, analysisStride: 3)
        }
    }
}

enum PipelineFramePolicy {
    static func canReuseMask(
        maskTimestamp: TimeInterval?,
        forFrameAt frameTimestamp: TimeInterval,
        maximumAge: TimeInterval = 0.28
    ) -> Bool {
        guard let maskTimestamp,
              frameTimestamp.isFinite,
              maskTimestamp.isFinite,
              frameTimestamp >= maskTimestamp else { return false }
        return frameTimestamp - maskTimestamp <= max(0, maximumAge)
    }
}
