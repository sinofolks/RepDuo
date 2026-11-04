import CoreMedia
import CoreVideo
import Foundation
import os

struct CameraPipelineMetrics: Equatable {
    let cameraFramesPerSecond: Double
    let visionLatencyMilliseconds: Double
    let analysisStride: Int
    let rendererQuality: RendererQuality
    let thermalState: PipelineThermalState
}

final class CameraVisionPipeline: NSObject {
    private struct AnalysisInput {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        let exercise: ExerciseType
        let trackingMode: BodyTrackingMode
        let generation: Int
    }

    private let cameraService: CameraService
    private let analyzer: VisionPoseAnalyzer
    private let analysisQueue = DispatchQueue(label: "com.repduo.vision.analysis", qos: .userInitiated)
    private let stateLock = NSLock()
    private let logger = Logger(subsystem: "com.repduo.ios", category: "vision.pose")
    private var analysisInFlight = false
    private var pendingAnalysis: AnalysisInput?
    private var lastMask: CVPixelBuffer?
    private var lastMaskTimestamp: TimeInterval?
    private var frameIndex = 0
    private var analysisStride = 2
    private var rendererQuality: RendererQuality = .balanced
    private var thermalState: PipelineThermalState = .nominal
    private var generation = 0
    private var exercise: ExerciseType = .squat
    private var trackingMode: BodyTrackingMode = .fullBody
    private weak var renderView: NeonCameraView?
    private let maximumMaskAge: TimeInterval = 0.28
    private var metricWindowStartedAt = ProcessInfo.processInfo.systemUptime
    private var metricFrameCount = 0
    private var lastVisionLatencyMilliseconds = 0.0
    private var silhouette: SkinnedSilhouette?
    private var silhouetteVersion = 0

    var onPoseFrame: ((PoseFrame) -> Void)?
    var onError: ((Error) -> Void)?
    var onCameraStateChange: ((CameraRuntimeState) -> Void)?
    var onRendererQualityChange: ((RendererQuality) -> Void)?
    var onMetrics: ((CameraPipelineMetrics) -> Void)?

    var isWideFramingAvailable: Bool { cameraService.isWideFramingAvailable }

    override init() {
        cameraService = CameraService()
        analyzer = VisionPoseAnalyzer()
        super.init()
        cameraService.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        thermalStateChanged()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func attach(renderView: NeonCameraView) {
        self.renderView = renderView
        stateLock.lock()
        let current = silhouette
        stateLock.unlock()
        renderView.setSilhouette(current)
    }

    func start(
        exercise: ExerciseType,
        mirrorFrontCamera: Bool,
        framingMode: CameraFramingMode,
        trackingMode: BodyTrackingMode = .fullBody
    ) {
        stateLock.lock()
        generation += 1
        self.exercise = exercise
        self.trackingMode = trackingMode
        frameIndex = 0
        metricWindowStartedAt = ProcessInfo.processInfo.systemUptime
        metricFrameCount = 0
        pendingAnalysis = nil
        lastMask = nil
        lastMaskTimestamp = nil
        stateLock.unlock()
        analysisQueue.async { [weak self] in self?.analyzer.reset() }
        cameraService.start(mirrorFrontCamera: mirrorFrontCamera, framingMode: framingMode)
    }

    func setTrackingMode(_ trackingMode: BodyTrackingMode) {
        stateLock.lock()
        guard self.trackingMode != trackingMode else {
            stateLock.unlock()
            return
        }
        self.trackingMode = trackingMode
        generation += 1
        pendingAnalysis = nil
        lastMask = nil
        lastMaskTimestamp = nil
        stateLock.unlock()
        renderView?.clearFrame()
        // A different framing needs a new outline.
        analysisQueue.async { [weak self] in
            self?.analyzer.reset()
            self?.analyzer.resetCalibration()
        }
    }

    func setFramingMode(
        _ framingMode: CameraFramingMode,
        completion: @escaping (Result<CameraFramingMode, Error>) -> Void
    ) {
        cameraService.setFramingMode(framingMode) { [weak self] result in
            guard let self else { return }
            if case .success = result {
                self.stateLock.lock()
                self.generation += 1
                self.pendingAnalysis = nil
                self.lastMask = nil
                self.lastMaskTimestamp = nil
                self.stateLock.unlock()
                self.renderView?.clearFrame()
                self.analysisQueue.async { [weak self] in self?.analyzer.reset() }
            }
            completion(result)
        }
    }

    func stop() {
        cameraService.stop()
        stateLock.lock()
        generation += 1
        pendingAnalysis = nil
        lastMask = nil
        lastMaskTimestamp = nil
        stateLock.unlock()
        renderView?.clearFrame()
        renderView = nil
        onPoseFrame = nil
        onError = nil
        onCameraStateChange = nil
        onRendererQualityChange = nil
        onMetrics = nil
    }

    @objc private func thermalStateChanged() {
        let thermalState: PipelineThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = .nominal
        case .fair: thermalState = .fair
        case .serious: thermalState = .serious
        case .critical: thermalState = .critical
        @unknown default: thermalState = .unknown
        }
        let policy = PipelinePerformancePolicy.policy(for: thermalState)
        stateLock.lock()
        self.thermalState = thermalState
        rendererQuality = policy.rendererQuality
        analysisStride = policy.analysisStride
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onRendererQualityChange?(policy.rendererQuality)
        }
    }

    private func performAnalysis(_ input: AnalysisInput) {
        let analysisStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            let result = try analyzer.analyze(
                pixelBuffer: input.pixelBuffer,
                timestamp: input.timestamp,
                exercise: input.exercise,
                trackingMode: input.trackingMode
            )
            stateLock.lock()
            let shouldPublish = input.generation == generation
            var silhouetteChanged = false
            if shouldPublish {
                lastMask = result.personMask
                lastMaskTimestamp = result.personMask == nil ? nil : input.timestamp
                if result.silhouetteVersion != silhouetteVersion {
                    silhouetteVersion = result.silhouetteVersion
                    silhouette = result.silhouette
                    silhouetteChanged = true
                }
            }
            let renderView = renderView
            stateLock.unlock()
            if shouldPublish {
                if silhouetteChanged { renderView?.setSilhouette(result.silhouette) }
                renderView?.updateBody(joints: result.poseFrame.joints, depth: result.depth)
                DispatchQueue.main.async { [weak self] in self?.onPoseFrame?(result.poseFrame) }
            }
        } catch {
            logger.error("Vision analysis failed: \(error.localizedDescription, privacy: .public)")
            stateLock.lock()
            if input.generation == generation {
                lastMask = nil
                lastMaskTimestamp = nil
            }
            stateLock.unlock()
        }
        stateLock.lock()
        lastVisionLatencyMilliseconds = (ProcessInfo.processInfo.systemUptime - analysisStartedAt) * 1_000
        stateLock.unlock()
        finishAnalysis()
    }

    private func finishAnalysis() {
        stateLock.lock()
        let next: AnalysisInput?
        if let pendingAnalysis,
           pendingAnalysis.generation == generation {
            next = pendingAnalysis
            self.pendingAnalysis = nil
        } else {
            next = nil
            if pendingAnalysis?.generation != generation { pendingAnalysis = nil }
            analysisInFlight = false
        }
        stateLock.unlock()

        if let next {
            analysisQueue.async { [weak self] in self?.performAnalysis(next) }
        }
    }
}

extension CameraVisionPipeline: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didChangeState state: CameraRuntimeState) {
        onCameraStateChange?(state)
    }

    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let timestamp = presentationTimestamp.isFinite
            ? presentationTimestamp
            : ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let mask: CVPixelBuffer?
        if PipelineFramePolicy.canReuseMask(
            maskTimestamp: lastMaskTimestamp,
            forFrameAt: timestamp,
            maximumAge: maximumMaskAge
        ) {
            mask = lastMask
        } else {
            mask = nil
        }
        let stride = analysisStride
        let currentExercise = exercise
        let currentTrackingMode = trackingMode
        let currentGeneration = generation
        frameIndex += 1
        let shouldAnalyze = frameIndex.isMultiple(of: stride)
        metricFrameCount += 1
        let now = ProcessInfo.processInfo.systemUptime
        let metricElapsed = now - metricWindowStartedAt
        let metrics: CameraPipelineMetrics?
        if metricElapsed >= 1 {
            metrics = CameraPipelineMetrics(
                cameraFramesPerSecond: Double(metricFrameCount) / metricElapsed,
                visionLatencyMilliseconds: lastVisionLatencyMilliseconds,
                analysisStride: stride,
                rendererQuality: rendererQuality,
                thermalState: thermalState
            )
            metricWindowStartedAt = now
            metricFrameCount = 0
        } else {
            metrics = nil
        }
        stateLock.unlock()
        renderView?.enqueue(pixelBuffer: pixelBuffer, mask: mask)
        if let metrics {
            DispatchQueue.main.async { [weak self] in self?.onMetrics?(metrics) }
        }

        guard shouldAnalyze else { return }
        let input = AnalysisInput(
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            exercise: currentExercise,
            trackingMode: currentTrackingMode,
            generation: currentGeneration
        )
        stateLock.lock()
        guard input.generation == generation else {
            stateLock.unlock()
            return
        }
        if analysisInFlight {
            pendingAnalysis = input
            stateLock.unlock()
            return
        }
        analysisInFlight = true
        stateLock.unlock()
        analysisQueue.async { [weak self] in
            self?.performAnalysis(input)
        }
    }

    func cameraService(_ service: CameraService, didFail error: Error) {
        onError?(error)
    }
}
