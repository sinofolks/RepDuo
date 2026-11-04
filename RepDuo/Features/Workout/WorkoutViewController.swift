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
    private let setTarget: Int
    private let personalBest: Int
    private let exerciseLabel = UILabel()
    private let repLabel = RDNumberLabel()
    private let phaseTag = RDTag(background: RDColor.warmWhite)
    private let recordTag = RDTag(text: "NEW RECORD", background: RDColor.ember)
    private let segmentBar = RDSegmentBar()
    private let targetLabel = UILabel()
    private let plusOneLabel = UILabel()
    private let flashRing = CAShapeLayer()
    private let promptLabel = UILabel()
    private var bystandersInView = false
    private let qualityPill = RDStatusPill(text: "TRACKING")
    private let coachScaleView = CoachScaleView()
    private let heartRateLabel = UILabel()
    private let audioRouteLabel = UILabel()
    private let pauseButton = RDIconButton(
        symbolName: "pause.fill",
        accessibilityLabel: "PAUSE",
        diameter: 64,
        background: RDColor.surfaceSecondary
    )
    private let finishButton = RDPrimaryButton(title: "FINISH SET", symbolName: "checkmark")
    private let pausedPanel = UIView()
    private let pausedRepsTile = RDStatTile(caption: "Completed", valueColor: RDColor.neonGreen, filled: false)
    private let pausedRemainingTile = RDStatTile(caption: "To target", filled: false)
    private let pausedScoreTile = RDStatTile(caption: "AI score", filled: false)
    private var topStack: UIStackView!
    private var countStack: UIView!
    private var infoStack: UIStackView!
    private var controlsStack: UIStackView!
    private var actionButtonsStack: UIStackView!
    private let countAreaGuide = UILayoutGuide()
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
        audioService: AudioRouteService,
        personalBest: Int = 0
    ) {
        self.setTarget = preferences.setRepTarget
        self.personalBest = personalBest
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
            self?.bystandersInView = frame.bystanderCount > 0
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
        exerciseLabel.setEyebrow(session.exercise.displayName, color: RDColor.textSecondary)
        repLabel.textColor = RDColor.neonGreen
        repLabel.textAlignment = .center
        repLabel.adjustsFontSizeToFitWidth = true
        repLabel.minimumScaleFactor = 0.4
        repLabel.accessibilityIdentifier = "workout.repCount"
        repLabel.layer.shadowColor = RDColor.neonGreen.cgColor
        repLabel.layer.shadowRadius = 22
        repLabel.layer.shadowOpacity = 0.4
        repLabel.layer.shadowOffset = .zero
        plusOneLabel.text = "+1"
        plusOneLabel.font = RDFont.numeric(34, maximumScale: 1)
        plusOneLabel.textColor = RDColor.warmWhite
        plusOneLabel.alpha = 0
        plusOneLabel.isAccessibilityElement = false
        plusOneLabel.translatesAutoresizingMaskIntoConstraints = false
        flashRing.fillColor = UIColor.clear.cgColor
        flashRing.lineWidth = 3
        flashRing.opacity = 0

        heartRateLabel.textColor = RDColor.ember
        heartRateLabel.font = RDFont.numeric(20, weight: .bold, italic: false)
        heartRateLabel.textAlignment = .right
        heartRateLabel.isHidden = true
        audioRouteLabel.textColor = RDColor.warmWhite
        audioRouteLabel.font = .systemFont(ofSize: 11, weight: .bold)
        audioRouteLabel.textAlignment = .right
        audioRouteLabel.numberOfLines = 2
        audioRouteLabel.isHidden = true

        promptLabel.textColor = RDColor.warmWhite
        promptLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 18, weight: .black),
            maximumPointSize: 26
        )
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 0
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.layer.shadowColor = UIColor.black.cgColor
        promptLabel.layer.shadowRadius = 6
        promptLabel.layer.shadowOpacity = 0.9
        promptLabel.layer.shadowOffset = .zero
        promptLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let topRight = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [exerciseLabel, heartRateLabel, audioRouteLabel])
        topRight.alignment = .trailing
        qualityPill.setContentHuggingPriority(.required, for: .horizontal)
        topStack = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [qualityPill, UIView(), topRight])
        topStack.alignment = .top

        let count = UIView()
        count.translatesAutoresizingMaskIntoConstraints = false
        count.layer.addSublayer(flashRing)
        repLabel.translatesAutoresizingMaskIntoConstraints = false
        count.addSubview(repLabel)
        count.addSubview(plusOneLabel)
        NSLayoutConstraint.activate([
            repLabel.leadingAnchor.constraint(equalTo: count.leadingAnchor),
            repLabel.trailingAnchor.constraint(equalTo: count.trailingAnchor),
            repLabel.topAnchor.constraint(equalTo: count.topAnchor),
            repLabel.bottomAnchor.constraint(equalTo: count.bottomAnchor),
            plusOneLabel.trailingAnchor.constraint(equalTo: count.trailingAnchor, constant: -12),
            plusOneLabel.topAnchor.constraint(equalTo: count.topAnchor, constant: 18)
        ])
        countStack = count

        let countCaption = UILabel()
        countCaption.setEyebrow("REPS".rdLocalized, kern: 3)
        countCaption.isAccessibilityElement = false
        recordTag.isHidden = true
        let tags = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [countCaption, phaseTag, recordTag])
        tags.alignment = .center
        targetLabel.font = RDFont.caption(weight: .medium)
        targetLabel.textColor = RDColor.textBody
        targetLabel.adjustsFontForContentSizeCategory = true
        targetLabel.textAlignment = .center
        infoStack = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [tags, segmentBar, targetLabel])
        infoStack.alignment = .center
        segmentBar.widthAnchor.constraint(equalToConstant: 280).isActive = true

        view.addLayoutGuide(countAreaGuide)
        view.addSubview(topStack)
        view.addSubview(countStack)
        view.addSubview(infoStack)

        pauseButton.accessibilityIdentifier = "workout.pause"
        pauseButton.addAction(UIAction { [weak self] _ in self?.togglePause() }, for: .touchUpInside)
        finishButton.accessibilityIdentifier = "workout.finish"
        finishButton.addAction(UIAction { [weak self] _ in self?.confirmFinish() }, for: .touchUpInside)
        actionButtonsStack = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [pauseButton, finishButton])
        actionButtonsStack.alignment = .center
        controlsStack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [coachScaleView, promptLabel, actionButtonsStack])
        view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDLayout.screenMargin),
            topStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDLayout.screenMargin),
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            countStack.centerXAnchor.constraint(equalTo: countAreaGuide.centerXAnchor),
            countStack.widthAnchor.constraint(lessThanOrEqualTo: countAreaGuide.widthAnchor),
            infoStack.centerXAnchor.constraint(equalTo: countAreaGuide.centerXAnchor),
            infoStack.topAnchor.constraint(equalTo: countStack.bottomAnchor, constant: 6),
            infoStack.widthAnchor.constraint(lessThanOrEqualTo: countAreaGuide.widthAnchor),
            countAreaGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDLayout.screenMargin),
            countAreaGuide.topAnchor.constraint(equalTo: topStack.bottomAnchor),
            finishButton.heightAnchor.constraint(equalToConstant: 64),
            controlsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -RDSpacing.md)
        ])

        portraitConstraints = [
            countAreaGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDLayout.screenMargin),
            countAreaGuide.bottomAnchor.constraint(equalTo: controlsStack.topAnchor),
            countStack.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 8),
            controlsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDSpacing.md),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDSpacing.md)
        ]
        landscapeConstraints = [
            countAreaGuide.trailingAnchor.constraint(equalTo: controlsStack.leadingAnchor, constant: -RDSpacing.md),
            countAreaGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            countStack.centerYAnchor.constraint(equalTo: countAreaGuide.centerYAnchor, constant: -30),
            controlsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDLayout.screenMargin),
            controlsStack.widthAnchor.constraint(equalToConstant: 380)
        ]

        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") || cameraAccess.state != .authorized {
            let demo = RDPrimaryButton(title: "+1", style: .secondary)
            demo.accessibilityIdentifier = "workout.simulateRep"
            demo.accessibilityLabel = "SIMULATE REP".rdLocalized
            demo.addAction(UIAction { [weak self] _ in self?.session.registerDebugRep() }, for: .touchUpInside)
            demo.widthAnchor.constraint(equalToConstant: 72).isActive = true
            demo.heightAnchor.constraint(equalToConstant: 64).isActive = true
            actionButtonsStack.insertArrangedSubview(demo, at: 1)
        }
        #endif

        configurePausedPanel()
        updateAdaptiveLayoutIfNeeded(force: true)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showDebugMetrics") {
            configureDebugPanel()
        }
        #endif
    }

    private func configurePausedPanel() {
        pausedPanel.backgroundColor = RDColor.surface
        pausedPanel.layer.cornerRadius = RDCornerRadius.large
        pausedPanel.translatesAutoresizingMaskIntoConstraints = false
        pausedPanel.isHidden = true
        pausedPanel.accessibilityIdentifier = "workout.pausedPanel"
        pausedPanel.accessibilityContainerType = .semanticGroup
        pausedPanel.accessibilityLabel = "Set paused. Tracking is frozen.".rdLocalized
        let icon = UIImageView(image: UIImage(
            systemName: "pause.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        ))
        icon.tintColor = RDColor.warmWhite
        icon.backgroundColor = RDColor.surfaceSecondary
        icon.contentMode = .center
        icon.layer.cornerRadius = 22
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])
        let title = UILabel()
        title.text = "SET PAUSED".rdLocalized
        title.textColor = RDColor.warmWhite
        title.font = RDFont.title(24)
        title.adjustsFontForContentSizeCategory = true
        let message = UILabel()
        message.text = "Tracking is frozen. Resume when you are in position.".rdLocalized
        message.textColor = RDColor.textSecondary
        message.font = RDFont.caption(weight: .regular)
        message.numberOfLines = 0
        message.adjustsFontForContentSizeCategory = true
        let titles = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [title, message])
        let header = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [icon, titles])
        header.alignment = .center
        let tiles = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [
            pausedRepsTile,
            pausedRemainingTile,
            pausedScoreTile
        ].map(wrapTile))
        tiles.distribution = .fillEqually
        let stack = UIStackView(axis: .vertical, spacing: 16, arrangedSubviews: [header, tiles])
        pausedPanel.addSubview(stack)
        stack.pinEdges(to: pausedPanel, insets: NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
        view.addSubview(pausedPanel)
        NSLayoutConstraint.activate([
            pausedPanel.leadingAnchor.constraint(equalTo: controlsStack.leadingAnchor),
            pausedPanel.trailingAnchor.constraint(equalTo: controlsStack.trailingAnchor),
            pausedPanel.bottomAnchor.constraint(equalTo: actionButtonsStack.topAnchor, constant: -12)
        ])
    }

    private func wrapTile(_ tile: RDStatTile) -> UIView {
        let container = UIView()
        container.backgroundColor = RDColor.background
        container.layer.cornerRadius = RDCornerRadius.small
        container.addSubview(tile)
        tile.pinEdges(to: container, insets: NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        return container
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
        let isRecord = personalBest > 0 && state.repCount > personalBest
        let tone = isRecord ? RDColor.ember : RDColor.neonGreen
        repLabel.text = String(state.repCount)
        repLabel.textColor = tone
        repLabel.layer.shadowColor = tone.cgColor
        phaseTag.text = state.phase.displayName
        recordTag.isHidden = !isRecord
        segmentBar.render(filled: state.repCount, total: setTarget, color: tone)
        targetLabel.text = targetText(for: state.repCount)
        if let coachingMessage = state.coachingMessage {
            promptLabel.text = coachingMessage
        } else if bystandersInView, state.poseQuality.permitsCounting {
            promptLabel.text = "Someone else is in view. Still counting only you.".rdLocalized
        } else {
            promptLabel.text = state.poseQuality.message
        }
        coachScaleView.render(state.lastRepCoaching)
        let qualityText: String
        switch state.poseQuality {
        case .excellent: qualityText = "TRACKING LOCKED".rdLocalized
        case .usable: qualityText = "TRACKING".rdLocalized
        case .unstable: qualityText = "LOW CONFIDENCE".rdLocalized
        case .missingRequiredJoints: qualityText = "BODY MISSING".rdLocalized
        case .multiplePeople: qualityText = "MULTIPLE PEOPLE".rdLocalized
        }
        if state.isPaused {
            qualityPill.update(text: "TRACKING STOPPED".rdLocalized, tone: RDColor.warning)
        } else {
            qualityPill.update(text: qualityText, tone: state.poseQuality.permitsCounting ? RDColor.neonGreen : RDColor.warning)
        }
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
        coachScaleView.alpha = state.isPaused ? 0 : 1
        promptLabel.alpha = state.isPaused ? 0 : 1
        countStack.alpha = state.isPaused ? 0.35 : 1
        if state.isPaused {
            pausedRepsTile.update(value: String(state.repCount))
            pausedRemainingTile.update(value: String(max(0, setTarget - state.repCount)))
            pausedScoreTile.update(value: coachScaleView.currentScore.map { String($0) } ?? "—")
        }
        pauseButton.setSymbol(state.isPaused ? "play.fill" : "pause.fill")
        pauseButton.accessibilityLabel = (state.isPaused ? "RESUME" : "PAUSE").rdLocalized
        pauseButton.configuration?.baseBackgroundColor = state.isPaused ? RDColor.neonGreen : RDColor.surfaceSecondary
        pauseButton.configuration?.baseForegroundColor = state.isPaused ? RDColor.background : RDColor.warmWhite
        if state.repCount > lastAnnouncedRep {
            lastAnnouncedRep = state.repCount
            UIAccessibility.post(notification: .announcement, argument: "%d reps".rdLocalizedFormat(state.repCount))
        }
        #if DEBUG
        renderDebugPanel()
        #endif
    }

    private func targetText(for reps: Int) -> String {
        if reps < setTarget {
            return "Target %1$d · %2$d to go".rdLocalizedFormat(setTarget, setTarget - reps)
        }
        if personalBest > 0 && reps <= personalBest {
            return "Target hit · %d more for a record".rdLocalizedFormat(personalBest - reps + 1)
        }
        if personalBest > 0 {
            return "New record · %d past your best".rdLocalizedFormat(reps - personalBest)
        }
        return "Target hit · keep going".rdLocalized
    }

    private func updateAdaptiveLayoutIfNeeded(force: Bool = false) {
        guard topStack != nil, controlsStack != nil else { return }
        let useLandscape = view.bounds.width > view.bounds.height
        guard force || useLandscape != lastUsesLandscapeLayout else { return }
        lastUsesLandscapeLayout = useLandscape
        NSLayoutConstraint.deactivate(useLandscape ? portraitConstraints : landscapeConstraints)
        NSLayoutConstraint.activate(useLandscape ? landscapeConstraints : portraitConstraints)
        coachScaleView.setCompactLayout(useLandscape)
        repLabel.font = RDFont.numeric(useLandscape ? 150 : 240, maximumScale: 1)
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
        let tone = repLabel.textColor ?? RDColor.neonGreen
        repLabel.textColor = RDColor.warmWhite
        guard !UIAccessibility.isReduceMotionEnabled else {
            UIView.transition(with: repLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.repLabel.textColor = tone
            }
            return
        }
        repLabel.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.repLabel.transform = .identity
        }
        UIView.transition(with: repLabel, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.repLabel.textColor = tone
        }

        let bounds = countStack.bounds
        let diameter = min(bounds.width, bounds.height) * 0.95
        flashRing.frame = bounds
        flashRing.path = UIBezierPath(ovalIn: CGRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )).cgPath
        flashRing.strokeColor = tone.cgColor
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1.45
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let ring = CAAnimationGroup()
        ring.animations = [scale, fade]
        ring.duration = 0.6
        ring.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flashRing.add(ring, forKey: "flash")

        plusOneLabel.layer.removeAllAnimations()
        plusOneLabel.transform = CGAffineTransform(translationX: 0, y: 10)
        plusOneLabel.alpha = 1
        UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.plusOneLabel.transform = CGAffineTransform(translationX: 0, y: -40)
            self.plusOneLabel.alpha = 0
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
