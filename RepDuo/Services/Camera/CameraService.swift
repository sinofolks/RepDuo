import AVFoundation
import os

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer)
    func cameraService(_ service: CameraService, didChangeState state: CameraRuntimeState)
    func cameraService(_ service: CameraService, didFail error: Error)
}

enum CameraFramingMode: String, CaseIterable, Equatable {
    case wide
    case standard

    static func resolved(requested: CameraFramingMode, isWideAvailable: Bool) -> CameraFramingMode {
        requested == .wide && !isWideAvailable ? .standard : requested
    }
}

enum CameraRuntimeState: Equatable {
    case idle
    case configuring
    case running
    case interrupted(String)
    case stopped
    case failed(String)
}

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case inputCreationFailed
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "No compatible camera is available.".rdLocalized
        case .inputCreationFailed: return "The camera input could not be created.".rdLocalized
        case .cannotAddInput: return "The camera input could not be attached.".rdLocalized
        case .cannotAddOutput: return "The video output could not be attached.".rdLocalized
        }
    }
}

final class CameraService: NSObject {
    let session = AVCaptureSession()
    weak var delegate: CameraServiceDelegate?

    private let logger = Logger(subsystem: "com.repduo.ios", category: "camera.session")
    private let sessionQueue = DispatchQueue(label: "com.repduo.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.repduo.camera.frames", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var mirrorFrontCamera = true
    private var cameraPosition: AVCaptureDevice.Position = .unspecified
    private var activeInput: AVCaptureDeviceInput?
    private var activeFramingMode: CameraFramingMode = .standard
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    var isWideFramingAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateWideCamera") { return true }
        #endif
        return Self.frontUltraWideCamera() != nil
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    deinit {
        rotationObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func start(mirrorFrontCamera: Bool, framingMode: CameraFramingMode) {
        self.mirrorFrontCamera = mirrorFrontCamera
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.emit(.configuring)
            do {
                let resolvedMode = CameraFramingMode.resolved(
                    requested: framingMode,
                    isWideAvailable: self.isWideFramingAvailable
                )
                if !self.configured {
                    try self.configure(framingMode: resolvedMode)
                } else if resolvedMode != self.activeFramingMode {
                    try self.replaceCameraInput(framingMode: resolvedMode)
                }
                self.updateConnectionConfiguration()
                if !self.session.isRunning { self.session.startRunning() }
                self.emit(.running)
                self.logger.info("Camera session started")
            } catch {
                self.logger.error("Camera configuration failed: \(error.localizedDescription, privacy: .public)")
                self.emit(.failed(error.localizedDescription))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.cameraService(self, didFail: error)
                }
            }
        }
    }

    func setFramingMode(
        _ framingMode: CameraFramingMode,
        completion: @escaping (Result<CameraFramingMode, Error>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let resolvedMode = CameraFramingMode.resolved(
                requested: framingMode,
                isWideAvailable: self.isWideFramingAvailable
            )
            guard self.configured else {
                DispatchQueue.main.async { completion(.success(resolvedMode)) }
                return
            }
            guard resolvedMode != self.activeFramingMode else {
                DispatchQueue.main.async { completion(.success(resolvedMode)) }
                return
            }

            self.emit(.configuring)
            do {
                try self.replaceCameraInput(framingMode: resolvedMode)
                self.updateConnectionConfiguration()
                self.emit(self.session.isRunning ? .running : .stopped)
                self.logger.info("Camera framing changed to \(resolvedMode.rawValue, privacy: .public)")
                DispatchQueue.main.async { completion(.success(resolvedMode)) }
            } catch {
                self.logger.error("Camera framing change failed: \(error.localizedDescription, privacy: .public)")
                self.emit(.failed(error.localizedDescription))
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.emit(.stopped)
            self.logger.info("Camera session stopped")
        }
    }

    private func emit(_ state: CameraRuntimeState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraService(self, didChangeState: state)
        }
    }

    private func configure(framingMode: CameraFramingMode) throws {
        guard let selection = cameraSelection(for: framingMode) else {
            throw CameraServiceError.cameraUnavailable
        }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: selection.device) }
        catch { throw CameraServiceError.inputCreationFailed }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            throw CameraServiceError.cannotAddOutput
        }
        session.addOutput(output)
        session.commitConfiguration()

        activeInput = input
        cameraPosition = selection.device.position
        activeFramingMode = selection.mode
        configureRotationCoordinator(for: selection.device)
        configureCaptureProperties(on: selection.device, framingMode: selection.mode)
        logActiveCamera(selection.device, framingMode: selection.mode)
        updateConnectionConfiguration()
        configured = true
    }

    private func replaceCameraInput(framingMode: CameraFramingMode) throws {
        guard let selection = cameraSelection(for: framingMode) else {
            throw CameraServiceError.cameraUnavailable
        }

        if activeInput?.device.uniqueID == selection.device.uniqueID {
            activeFramingMode = selection.mode
            configureCaptureProperties(on: selection.device, framingMode: selection.mode)
            return
        }

        let newInput: AVCaptureDeviceInput
        do { newInput = try AVCaptureDeviceInput(device: selection.device) }
        catch { throw CameraServiceError.inputCreationFailed }

        let previousInput = activeInput
        session.beginConfiguration()
        if let previousInput { session.removeInput(previousInput) }
        guard session.canAddInput(newInput) else {
            if let previousInput, session.canAddInput(previousInput) { session.addInput(previousInput) }
            session.commitConfiguration()
            throw CameraServiceError.cannotAddInput
        }
        session.addInput(newInput)
        session.commitConfiguration()

        activeInput = newInput
        cameraPosition = selection.device.position
        activeFramingMode = selection.mode
        configureRotationCoordinator(for: selection.device)
        configureCaptureProperties(on: selection.device, framingMode: selection.mode)
        logActiveCamera(selection.device, framingMode: selection.mode)
    }

    private func configureCaptureProperties(on device: AVCaptureDevice, framingMode: CameraFramingMode) {
        let supportsThirtyFramesPerSecond = device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        })
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if supportsThirtyFramesPerSecond {
                let duration = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            } else {
                logger.notice("Active camera format does not expose 30 FPS")
            }

            let standardCrop: CGFloat = device.deviceType == .builtInUltraWideCamera ? 1.35 : 1
            let requestedZoom = framingMode == .wide ? 1 : standardCrop
            device.videoZoomFactor = min(
                max(requestedZoom, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )
        } catch {
            logger.notice("Could not configure camera properties: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct CameraSelection {
        let device: AVCaptureDevice
        let mode: CameraFramingMode
    }

    private func cameraSelection(for framingMode: CameraFramingMode) -> CameraSelection? {
        if framingMode == .wide, let ultraWide = Self.frontUltraWideCamera() {
            return CameraSelection(device: ultraWide, mode: .wide)
        }
        if let standard = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return CameraSelection(device: standard, mode: .standard)
        }
        if let ultraWide = Self.frontUltraWideCamera() {
            return CameraSelection(device: ultraWide, mode: framingMode)
        }
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return CameraSelection(device: back, mode: .standard)
        }
        return nil
    }

    private static func frontUltraWideCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .front)
    }

    private func logActiveCamera(_ device: AVCaptureDevice, framingMode: CameraFramingMode) {
        logger.info("Active camera framing=\(framingMode.rawValue, privacy: .public) type=\(device.deviceType.rawValue, privacy: .public) fov=\(device.activeFormat.videoFieldOfView, privacy: .public)")
    }

    private func configureRotationCoordinator(for device: AVCaptureDevice) {
        rotationObservation?.invalidate()

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async { [weak self, weak coordinator] in
                guard let self,
                      let coordinator,
                      self.rotationCoordinator === coordinator else { return }
                self.updateConnectionConfiguration(rotationAngle: angle)
            }
        }
    }

    private func updateConnectionConfiguration(rotationAngle: CGFloat? = nil) {
        guard let connection = output.connection(with: .video) else { return }
        let resolvedAngle = rotationAngle
            ?? rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
            ?? 0
        if connection.isVideoRotationAngleSupported(resolvedAngle) {
            connection.videoRotationAngle = resolvedAngle
        } else {
            logger.notice("Camera rotation angle is unsupported: \(resolvedAngle, privacy: .public)")
        }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = cameraPosition == .front && mirrorFrontCamera
        }
    }

    @objc private func sessionInterrupted(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
            .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
        let message: String
        switch reason?.rawValue {
        case AVCaptureSession.InterruptionReason.audioDeviceInUseByAnotherClient.rawValue:
            message = "Camera audio is in use by another app.".rdLocalized
        case AVCaptureSession.InterruptionReason.videoDeviceInUseByAnotherClient.rawValue:
            message = "Camera is in use by another app.".rdLocalized
        case AVCaptureSession.InterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.rawValue:
            message = "Camera is unavailable while multiple apps are active.".rdLocalized
        case AVCaptureSession.InterruptionReason.videoDeviceNotAvailableDueToSystemPressure.rawValue:
            message = "Camera paused because the device is under pressure.".rdLocalized
        case AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground.rawValue:
            message = "Camera is unavailable in the background.".rdLocalized
        case 6:
            message = "Camera content is temporarily hidden by a system privacy safeguard.".rdLocalized
        default:
            message = "The camera session was interrupted.".rdLocalized
        }
        emit(.interrupted(message))
        let error = NSError(
            domain: "com.repduo.camera",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "%@ Resume when the camera is available.".rdLocalizedFormat(message)]
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraService(self, didFail: error)
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
            self.emit(.running)
            self.logger.info("Camera interruption ended")
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            ?? NSError(domain: "com.repduo.camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Camera runtime error.".rdLocalized])
        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain,
           nsError.code == AVError.Code.mediaServicesWereReset.rawValue {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.startRunning()
                self.emit(.running)
                self.logger.info("Camera restarted after media services reset")
            }
            return
        }
        emit(.failed(error.localizedDescription))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraService(self, didFail: error)
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.cameraService(self, didOutput: sampleBuffer)
    }
}
