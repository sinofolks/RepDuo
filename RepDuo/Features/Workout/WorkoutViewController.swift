import CoreImage
import UIKit
import Vision

final class WorkoutViewController: RDBaseViewController {
    private let session: WorkoutSession
    private let pipeline: CameraVisionPipeline
    private let cameraAccess: CameraAuthorizationService
    private let feedback: FeedbackService
    private let preferences: AppPreferences
    private let audioService: AudioRouteService
    private let cameraView = NeonCameraView()
    private let fallbackImageView = UIImageView()
    private let exerciseLabel = UILabel()
    private let repLabel = UILabel()
    private let phaseLabel = UILabel()
    private let promptLabel = UILabel()
    private let qualityPill = UILabel()
    private let coachScaleView = CoachScaleView()
    private let heartRateLabel = UILabel()
    private let audioRouteLabel = UILabel()
    private let pauseButton = RDPrimaryButton(title: "PAUSE", style: .secondary)
    private let finishButton = RDPrimaryButton(title: "FINISH SET", style: .secondary)
    private let pausedPanel = UIView()
    private var topStack: UIStackView!
    private var countStack: UIStackView!
    private var controlsStack: UIStackView!
    private var actionButtonsStack: UIStackView!
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var lastUsesLandscapeLayout: Bool?
    private var backgroundObserver: NSObjectProtocol?
    private var lastAnnouncedRep = 0
    private var lastSpokenFormRep = 0
    private var isPresentingCameraError = false
    private var audioRouteHideWorkItem: DispatchWorkItem?
    #if DEBUG
    private let debugLabel = UILabel()
    private var debugMetrics: CameraPipelineMetrics?
    private var debugMetalMetrics: MetalRenderMetrics?
    private var debugAngle: Double?
    private var debugPoseQuality: PoseQuality = .unstable
    private var debugRepEvents: [String] = []
    #endif

    var onFinish: ((WorkoutSummary) -> Void)?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    init(
        session: WorkoutSession,
        pipeline: CameraVisionPipeline,
        cameraAccess: CameraAuthorizationService,
        feedback: FeedbackService,
        preferences: AppPreferences,
        audioService: AudioRouteService
    ) {
        self.session = session
        self.pipeline = pipeline
        self.cameraAccess = cameraAccess
        self.feedback = feedback
        self.preferences = preferences
        self.audioService = audioService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        view.backgroundColor = RDColor.backgroundDeep
        configureCameraSurface()
        configureOverlay()
        bindSession()
        render(session.state)

        pipeline.onPoseFrame = { [weak self] frame in
            #if DEBUG
            self?.debugAngle = frame.primaryAngle
            self?.debugPoseQuality = frame.quality
            self?.renderDebugPanel()
            #endif
            self?.session.process(frame)
        }
        pipeline.onRendererQualityChange = { [weak self] quality in self?.session.setRendererQuality(quality) }
        pipeline.onError = { [weak self] error in self?.handleCameraError(error) }
        pipeline.onCameraStateChange = { [weak self] state in
            guard let self else { return }
            if case .interrupted = state { self.session.pause() }
            if case .failed = state { self.session.pause() }
        }
        audioService.onInterruption = { [weak self] began in
            if began { self?.session.pause() }
        }
        audioService.onChange = { [weak self] status in self?.showAudioRoute(status) }
        #if DEBUG
        pipeline.onMetrics = { [weak self] metrics in
            self?.debugMetrics = metrics
            self?.renderDebugPanel()
        }
        cameraView.onRenderMetrics = { [weak self] metrics in
            self?.debugMetalMetrics = metrics
            self?.renderDebugPanel()
        }
        #endif
        if cameraAccess.state == .authorized { pipeline.attach(renderView: cameraView) }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.session.pause() }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAdaptiveLayoutIfNeeded()
    }

    private func configureCameraSurface() {
        let fallbackImage = UIImage(named: session.exercise.demoImageName)
        fallbackImageView.image = fallbackImage
        if let fallbackImage {
            BlackStageImageProcessor.render(fallbackImage) { [weak self] processed in
                if let processed { self?.fallbackImageView.image = processed }
            }
        }
        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.clipsToBounds = true
        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        view.addSubview(fallbackImageView)
        cameraView.pinEdges(to: view)
        fallbackImageView.pinEdges(to: view)
        cameraView.isHidden = false
        fallbackImageView.isHidden = cameraAccess.state == .authorized
        cameraView.intensity = preferences.neonIntensity
        cameraView.replacesBackground = true

        let gradient = RDGradientOverlayView()
        gradient.direction = .both
        view.addSubview(gradient)
        gradient.pinEdges(to: view)
    }

    private func configureOverlay() {
        exerciseLabel.text = session.exercise.displayName
        exerciseLabel.textColor = RDColor.warmWhite
        exerciseLabel.font = RDFont.body(weight: .black)
        exerciseLabel.adjustsFontForContentSizeCategory = true
        repLabel.textColor = RDColor.warmWhite
        repLabel.font = RDFont.display(92)
        repLabel.adjustsFontForContentSizeCategory = true
        repLabel.adjustsFontSizeToFitWidth = true
        repLabel.accessibilityIdentifier = "workout.repCount"
        phaseLabel.textColor = RDColor.neonGreen
        phaseLabel.font = .systemFont(ofSize: 14, weight: .black)
        phaseLabel.textAlignment = .center
        qualityPill.textColor = RDColor.neonGreen
        qualityPill.font = .systemFont(ofSize: 11, weight: .bold)
        qualityPill.numberOfLines = 2
        qualityPill.textAlignment = .right
        heartRateLabel.textColor = RDColor.warmWhite
        heartRateLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        heartRateLabel.textAlignment = .right
        heartRateLabel.isHidden = true
        audioRouteLabel.textColor = RDColor.warmWhite
        audioRouteLabel.font = .systemFont(ofSize: 11, weight: .bold)
        audioRouteLabel.textAlignment = .right
        audioRouteLabel.numberOfLines = 2
        audioRouteLabel.isHidden = true

        promptLabel.textColor = RDColor.warmWhite
        promptLabel.backgroundColor = .clear
        promptLabel.font = RDFont.body(weight: .bold)
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 0
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let topRight = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [qualityPill, heartRateLabel, audioRouteLabel])
        topRight.alignment = .trailing
        topStack = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [exerciseLabel, topRight])
        topStack.distribution = .equalSpacing

        let countCaption = UILabel()
        countCaption.text = "REPS".rdLocalized
        countCaption.textColor = RDColor.textSecondary
        countCaption.font = .systemFont(ofSize: 11, weight: .bold)
        countCaption.textAlignment = .center
        countStack = UIStackView(axis: .vertical, spacing: 1, arrangedSubviews: [repLabel, countCaption, phaseLabel])
        countStack.alignment = .center
        view.addSubview(topStack)
        view.addSubview(countStack)
        view.addSubview(coachScaleView)

        pauseButton.accessibilityIdentifier = "workout.pause"
        pauseButton.configuration?.baseBackgroundColor = RDColor.surface.withAlphaComponent(0.58)
        pauseButton.addAction(UIAction { [weak self] _ in self?.togglePause() }, for: .touchUpInside)
        finishButton.accessibilityIdentifier = "workout.finish"
        finishButton.configuration?.baseBackgroundColor = RDColor.surface.withAlphaComponent(0.58)
        finishButton.configuration?.baseForegroundColor = RDColor.neonGreen
        finishButton.addAction(UIAction { [weak self] _ in self?.confirmFinish() }, for: .touchUpInside)
        actionButtonsStack = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [pauseButton, finishButton])
        actionButtonsStack.distribution = .fillEqually
        controlsStack = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [promptLabel, actionButtonsStack])
        view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            topStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDSpacing.lg),
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            repLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 106),
            coachScaleView.widthAnchor.constraint(equalToConstant: 112),
            controlsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -RDSpacing.md)
        ])

        portraitConstraints = [
            countStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            countStack.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: RDSpacing.md),
            countStack.trailingAnchor.constraint(lessThanOrEqualTo: coachScaleView.leadingAnchor, constant: -12),
            coachScaleView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 10),
            coachScaleView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: RDSpacing.md),
            coachScaleView.bottomAnchor.constraint(lessThanOrEqualTo: controlsStack.topAnchor, constant: -12),
            controlsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDSpacing.lg)
        ]
        landscapeConstraints = [
            countStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            countStack.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 4),
            countStack.trailingAnchor.constraint(lessThanOrEqualTo: coachScaleView.leadingAnchor, constant: -12),
            coachScaleView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 10),
            coachScaleView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 4),
            coachScaleView.bottomAnchor.constraint(lessThanOrEqualTo: controlsStack.topAnchor, constant: -8),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDSpacing.lg),
            controlsStack.widthAnchor.constraint(equalToConstant: 360)
        ]

        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let demo = RDPrimaryButton(title: "SIMULATE REP", style: .secondary, symbolName: "plus")
            demo.accessibilityIdentifier = "workout.simulateRep"
            demo.addAction(UIAction { [weak self] _ in self?.session.registerDebugRep() }, for: .touchUpInside)
            controlsStack.insertArrangedSubview(demo, at: 1)
        }
        #endif

        updateAdaptiveLayoutIfNeeded(force: true)

        configurePausedPanel()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showDebugMetrics") {
            configureDebugPanel()
        }
        #endif
    }

    private func configurePausedPanel() {
        pausedPanel.backgroundColor = RDColor.background.withAlphaComponent(0.9)
        pausedPanel.layer.cornerRadius = RDCornerRadius.large
        pausedPanel.translatesAutoresizingMaskIntoConstraints = false
        pausedPanel.isHidden = true
        pausedPanel.accessibilityIdentifier = "workout.pausedPanel"
        pausedPanel.isAccessibilityElement = true
        pausedPanel.accessibilityLabel = "Set paused. Tracking is frozen.".rdLocalized
        let icon = UIImageView(image: UIImage(systemName: "pause.circle.fill"))
        icon.tintColor = RDColor.neonGreen
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = UILabel()
        title.text = "SET PAUSED".rdLocalized
        title.textColor = RDColor.warmWhite
        title.font = RDFont.title(24)
        title.textAlignment = .center
        let message = UILabel()
        message.text = "Tracking is frozen. Resume when you are in position.".rdLocalized
        message.textColor = RDColor.textSecondary
        message.font = RDFont.body()
        message.numberOfLines = 0
        message.textAlignment = .center
        let stack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [icon, title, message])
        pausedPanel.addSubview(stack)
        stack.pinEdges(to: pausedPanel, insets: NSDirectionalEdgeInsets(top: 24, leading: 22, bottom: 24, trailing: 22))
        view.addSubview(pausedPanel)
        NSLayoutConstraint.activate([
            pausedPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pausedPanel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pausedPanel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: RDSpacing.lg),
            pausedPanel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -RDSpacing.lg)
        ])
    }

    private func bindSession() {
        session.onStateChange = { [weak self] state, completedRep in
            self?.render(state)
            if completedRep {
                #if DEBUG
                let elapsed = ProcessInfo.processInfo.systemUptime
                self?.debugRepEvents.append("#\(state.repCount) @ \(String(format: "%.1f", elapsed))")
                if let count = self?.debugRepEvents.count, count > 3 {
                    self?.debugRepEvents.removeFirst(count - 3)
                }
                self?.renderDebugPanel()
                #endif
                self?.feedback.repCompleted()
                self?.pulseCounter()
                self?.cameraView.triggerCompletionPulse()
                if let result = state.lastRepCoaching,
                   result.repNumber != self?.lastSpokenFormRep,
                   result.shouldSpeak,
                   let issue = result.primaryIssue {
                    self?.lastSpokenFormRep = result.repNumber
                    self?.feedback.formIssue(issue)
                }
            } else if !state.isPaused, !state.poseQuality.permitsCounting {
                self?.feedback.trackingIssue(state.poseQuality.message)
            }
        }
    }

    private func render(_ state: WorkoutViewState) {
        repLabel.text = String(state.repCount)
        phaseLabel.text = state.phase.displayName
        renderPrompt(state.coachingMessage ?? state.poseQuality.message)
        coachScaleView.render(state.lastRepCoaching)
        let qualityText: String
        switch state.poseQuality {
        case .excellent: qualityText = "● TRACKING LOCKED".rdLocalized
        case .usable: qualityText = "● TRACKING".rdLocalized
        case .unstable: qualityText = "● LOW CONFIDENCE".rdLocalized
        case .missingRequiredJoints: qualityText = "● BODY MISSING".rdLocalized
        case .multiplePeople: qualityText = "● MULTIPLE PEOPLE".rdLocalized
        }
        qualityPill.text = qualityText
        qualityPill.textColor = state.poseQuality.permitsCounting ? RDColor.neonGreen : RDColor.warning
        switch state.rendererQuality {
        case .high: cameraView.intensity = preferences.neonIntensity
        case .balanced: cameraView.intensity = preferences.neonIntensity * 0.9
        case .lowPower: cameraView.intensity = preferences.neonIntensity * 0.72
        case .thermalSafe: cameraView.intensity = preferences.neonIntensity * 0.55
        }
        cameraView.rendererQuality = state.rendererQuality
        cameraView.trackingConfidence = state.poseQuality.permitsCounting ? 1 : 0.52
        if let heartRate = state.heartRate {
            heartRateLabel.text = "♥ %d BPM".rdLocalizedFormat(heartRate)
            heartRateLabel.isHidden = false
        } else {
            heartRateLabel.isHidden = true
        }
        pausedPanel.isHidden = !state.isPaused
        pauseButton.configuration?.title = (state.isPaused ? "RESUME" : "PAUSE").rdLocalized
        if state.repCount > lastAnnouncedRep {
            lastAnnouncedRep = state.repCount
            UIAccessibility.post(notification: .announcement, argument: "%d reps".rdLocalizedFormat(state.repCount))
        }
        #if DEBUG
        renderDebugPanel()
        #endif
    }

    private func renderPrompt(_ message: String) {
        let prefix = "MAIN ADVICE".rdLocalized.uppercased() + "  "
        let value = NSMutableAttributedString(
            string: prefix,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .black),
                .foregroundColor: RDColor.neonGreen
            ]
        )
        value.append(NSAttributedString(
            string: message,
            attributes: [
                .font: RDFont.body(weight: .bold),
                .foregroundColor: RDColor.warmWhite
            ]
        ))
        promptLabel.attributedText = value
        promptLabel.accessibilityLabel = "%1$@, %2$@".rdLocalizedFormat(
            "Main advice".rdLocalized,
            message
        )
    }

    private func updateAdaptiveLayoutIfNeeded(force: Bool = false) {
        guard topStack != nil, controlsStack != nil else { return }
        let useLandscape = view.bounds.width > view.bounds.height
        guard force || useLandscape != lastUsesLandscapeLayout else { return }
        lastUsesLandscapeLayout = useLandscape
        NSLayoutConstraint.deactivate(useLandscape ? portraitConstraints : landscapeConstraints)
        NSLayoutConstraint.activate(useLandscape ? landscapeConstraints : portraitConstraints)
        coachScaleView.setCompactLayout(useLandscape)
        repLabel.font = RDFont.display(useLandscape ? 76 : 108)
        view.layoutIfNeeded()
    }

    private func togglePause() {
        if session.state.isPaused { session.resume() } else { session.pause() }
    }

    private func confirmFinish() {
        let wasPaused = session.state.isPaused
        if !wasPaused { session.pause() }
        let alert = UIAlertController(
            title: "Finish this set?".rdLocalized,
            message: "Your reps and active time will be saved.".rdLocalized,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Keep training".rdLocalized, style: .cancel) { [weak self] _ in
            if !wasPaused { self?.session.resume() }
        })
        alert.addAction(UIAlertAction(title: "Finish set".rdLocalized, style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.pipeline.stop()
            self.feedback.workoutCompleted()
            self.onFinish?(self.session.finish())
        })
        present(alert, animated: true)
    }

    private func pulseCounter() {
        repLabel.transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
        repLabel.textColor = RDColor.neonBright
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.2) {
            self.repLabel.transform = .identity
            self.repLabel.textColor = RDColor.warmWhite
        }
    }

    private func handleCameraError(_ error: Error) {
        session.pause()
        guard !isPresentingCameraError else { return }
        isPresentingCameraError = true
        let alert = UIAlertController(
            title: "Camera paused".rdLocalized,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK".rdLocalized, style: .default) { [weak self] _ in
            self?.isPresentingCameraError = false
        })
        present(alert, animated: true)
    }

    private func showAudioRoute(_ status: AudioRouteStatus) {
        audioRouteHideWorkItem?.cancel()
        audioRouteLabel.text = (status.isBluetooth ? "HEADPHONES · %@" : "AUDIO · %@")
            .rdLocalizedFormat(status.outputName.uppercased())
        audioRouteLabel.isHidden = false
        let workItem = DispatchWorkItem { [weak self] in self?.audioRouteLabel.isHidden = true }
        audioRouteHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    #if DEBUG
    private func configureDebugPanel() {
        debugLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        debugLabel.textColor = RDColor.neonBright
        debugLabel.backgroundColor = RDColor.background.withAlphaComponent(0.78)
        debugLabel.numberOfLines = 0
        debugLabel.layer.cornerRadius = 8
        debugLabel.layer.masksToBounds = true
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        debugLabel.accessibilityIdentifier = "workout.debugMetrics"
        view.addSubview(debugLabel)
        NSLayoutConstraint.activate([
            debugLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -RDSpacing.lg),
            debugLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
            debugLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 185)
        ])
        renderDebugPanel()
    }

    private func renderDebugPanel() {
        guard debugLabel.superview != nil else { return }
        let fps = debugMetrics.map { String(format: "%.1f", $0.cameraFramesPerSecond) } ?? "—"
        let latency = debugMetrics.map { String(format: "%.1f", $0.visionLatencyMilliseconds) } ?? "—"
        let stride = debugMetrics.map { String($0.analysisStride) } ?? "—"
        let angle = debugAngle.map { String(format: "%.1f°", $0) } ?? "—"
        let gpu = debugMetalMetrics.map { String(format: "%.2f", $0.gpuDurationMilliseconds) } ?? "—"
        let quality = debugMetrics?.rendererQuality.rawValue ?? session.state.rendererQuality.rawValue
        let thermal = debugMetrics?.thermalState.rawValue.uppercased() ?? "—"
        let events = debugRepEvents.isEmpty ? "—" : debugRepEvents.joined(separator: " · ")
        debugLabel.text = "  CAM \(fps) FPS\n  VISION \(latency) MS · /\(stride)\n  GPU \(gpu) MS · \(thermal)\n  \(session.state.phase.rawValue) · \(debugPoseQuality.debugName.uppercased())\n  ANGLE \(angle) · \(quality.uppercased())\n  REPS \(events)  "
    }
    #endif
}

private enum BlackStageImageProcessor {
    private static let context = CIContext()

    static func render(_ image: UIImage, completion: @escaping (UIImage?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let maskBuffer = request.results?.first?.pixelBuffer else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let source = CIImage(cgImage: cgImage)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let scaledMask = mask
                .transformed(by: CGAffineTransform(
                    scaleX: source.extent.width / max(mask.extent.width, 1),
                    y: source.extent.height / max(mask.extent.height, 1)
                ))
                .cropped(to: source.extent)
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2.0])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
                .cropped(to: source.extent)
            let blackStage = CIImage(
                color: CIColor(red: 0.063, green: 0.075, blue: 0.09, alpha: 1)
            ).cropped(to: source.extent)
            let isolated = source.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: blackStage,
                    kCIInputMaskImageKey: scaledMask
                ]
            ).cropped(to: source.extent)
            let output = context.createCGImage(isolated, from: source.extent).map {
                UIImage(cgImage: $0, scale: image.scale, orientation: .up)
            }
            DispatchQueue.main.async { completion(output) }
        }
    }
}
