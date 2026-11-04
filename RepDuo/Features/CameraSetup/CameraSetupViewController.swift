import UIKit

final class CameraSetupViewController: RDBaseViewController {
    private let exercise: ExerciseType
    private let pipeline: CameraVisionPipeline
    private let preferences: AppPreferences
    private let cameraAccess: CameraAuthorizationService
    private let cameraView = NeonCameraView()
    private let fallbackImageView = UIImageView()
    private let guideOverlay = RDCameraGuideOverlay()
    private let statusLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let continueButton = RDPrimaryButton(title: "HOLD YOUR POSITION")
    private let framingButton = UIButton(type: .system)
    private let trackingModeControl = UISegmentedControl(items: BodyTrackingMode.allCases.map(\.segmentTitle))
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private var stableSince: Date?
    private var isPositionLocked = false
    private var isChangingFramingMode = false
    private var isCompletingWithGesture = false
    private var hasContinued = false
    private var framingMode: CameraFramingMode = .standard
    private var trackingMode: BodyTrackingMode
    private var gestureDetector = CalibrationConfirmationGestureDetector()
    private var gestureCompletionWorkItem: DispatchWorkItem?
    private let requiredStableDuration: TimeInterval = 0.8

    var onContinue: (() -> Void)?

    init(
        exercise: ExerciseType,
        pipeline: CameraVisionPipeline,
        preferences: AppPreferences,
        cameraAccess: CameraAuthorizationService
    ) {
        self.exercise = exercise
        self.pipeline = pipeline
        self.preferences = preferences
        self.cameraAccess = cameraAccess
        trackingMode = preferences.bodyTrackingMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        useCameraStageAppearance()
        framingMode = CameraFramingMode.resolved(
            requested: preferences.prefersWideCamera ? .wide : .standard,
            isWideAvailable: pipeline.isWideFramingAvailable
        )
        configureCameraSurface()
        configureOverlay()
        pipeline.onPoseFrame = { [weak self] frame in self?.consume(frame) }
        pipeline.onError = { [weak self] error in self?.showCameraError(error) }
        pipeline.onCameraStateChange = { [weak self] state in self?.render(cameraState: state) }
        if cameraAccess.state == .authorized {
            pipeline.attach(renderView: cameraView)
            pipeline.start(
                exercise: exercise,
                mirrorFrontCamera: preferences.mirrorFrontCamera,
                framingMode: framingMode,
                trackingMode: trackingMode
            )
        } else {
            enterDemoReadyState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        gestureCompletionWorkItem?.cancel()
        if isMovingFromParent { pipeline.stop() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let usesCompactCameraLayout = traitCollection.verticalSizeClass == .compact || view.bounds.height < 500
        eyebrowLabel.isHidden = usesCompactCameraLayout
    }

    private func configureCameraSurface() {
        fallbackImageView.image = UIImage(named: exercise.demoImageName)
        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.clipsToBounds = true
        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        view.addSubview(fallbackImageView)
        cameraView.pinEdges(to: view)
        fallbackImageView.pinEdges(to: view)
        fallbackImageView.isHidden = cameraAccess.state == .authorized

        let shade = RDGradientOverlayView()
        shade.direction = .both
        view.addSubview(shade)
        shade.pinEdges(to: view)

        view.addSubview(guideOverlay)
        guideOverlay.pinEdges(to: view)
    }

    private func configureOverlay() {
        configureFramingButton()
        configureTrackingModeControl()
        eyebrowLabel.setEyebrow("SETUP".rdLocalized)
        titleLabel.font = RDFont.title(28)
        titleLabel.textColor = RDColor.label
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        renderTrackingMode()
        statusLabel.textColor = RDColor.label
        statusLabel.font = RDFont.body(weight: .medium)
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.text = trackingMode.instruction(for: exercise)
        progressView.trackTintColor = RDColor.fill
        progressView.progressTintColor = RDColor.accent
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        continueButton.isEnabled = false
        continueButton.accessibilityIdentifier = "setup.continue"
        continueButton.accessibilityHint = "You can also raise one hand briefly to continue without touching the phone.".rdLocalized
        continueButton.addAction(UIAction { [weak self] _ in self?.continueNow() }, for: .touchUpInside)

        let manual = UIButton(type: .system)
        manual.setTitle("CONTINUE ANYWAY".rdLocalized, for: .normal)
        manual.setTitleColor(RDColor.secondaryLabel, for: .normal)
        manual.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        manual.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        manual.accessibilityHint = "Skips the position check and may reduce counting accuracy.".rdLocalized
        manual.addAction(UIAction { [weak self] _ in self?.confirmManualContinue() }, for: .touchUpInside)

        let titles = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [eyebrowLabel, titleLabel])
        let header = UIStackView(axis: .horizontal, spacing: RDSpacing.sm, arrangedSubviews: [titles, framingButton])
        header.alignment = .top
        let top = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [header, trackingModeControl])
        view.addSubview(top)

        let hand = UIImageView(image: UIImage(systemName: "hand.raised"))
        hand.tintColor = RDColor.accent
        hand.setContentHuggingPriority(.required, for: .horizontal)
        let gestureHint = makeLabel(
            text: "Raise one hand and hold for a second to start hands-free",
            font: RDFont.caption(weight: .regular),
            color: RDColor.secondaryLabel
        )
        let hintRow = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [hand, gestureHint])
        hintRow.alignment = .center
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = RDColor.card.withAlphaComponent(0.94)
        panel.layer.cornerRadius = RDCornerRadius.medium
        let bottom = UIStackView(
            axis: .vertical,
            spacing: 12,
            arrangedSubviews: [statusLabel, progressView, hintRow, continueButton, manual]
        )
        bottom.setCustomSpacing(4, after: continueButton)
        panel.addSubview(bottom)
        bottom.pinEdges(to: panel, insets: NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 4, trailing: 16))
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: RDLayout.screenMargin),
            top.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -RDLayout.screenMargin),
            top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func configureTrackingModeControl() {
        trackingModeControl.accessibilityIdentifier = "setup.trackingMode"
        trackingModeControl.accessibilityLabel = "Body tracking mode".rdLocalized
        trackingModeControl.accessibilityHint = "Choose accurate full-body tracking or rough partial-body tracking.".rdLocalized
        trackingModeControl.selectedSegmentTintColor = RDColor.accent
        trackingModeControl.backgroundColor = RDColor.background.withAlphaComponent(0.82)
        trackingModeControl.setTitleTextAttributes([
            .foregroundColor: RDColor.label,
            .font: UIFont.systemFont(ofSize: 13, weight: .bold)
        ], for: .normal)
        trackingModeControl.setTitleTextAttributes([
            .foregroundColor: RDColor.background,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ], for: .selected)
        trackingModeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        trackingModeControl.addAction(UIAction { [weak self] _ in
            self?.trackingModeChanged()
        }, for: .valueChanged)
    }

    private func renderTrackingMode() {
        trackingModeControl.selectedSegmentIndex = BodyTrackingMode.allCases.firstIndex(of: trackingMode) ?? 0
        titleLabel.text = exercise.displayName
        if !isPositionLocked {
            statusLabel.text = trackingMode.instruction(for: exercise)
        }
    }

    private func trackingModeChanged() {
        let modes = BodyTrackingMode.allCases
        guard modes.indices.contains(trackingModeControl.selectedSegmentIndex) else { return }
        let selectedMode = modes[trackingModeControl.selectedSegmentIndex]
        guard selectedMode != trackingMode else { return }
        trackingMode = selectedMode
        preferences.bodyTrackingMode = selectedMode
        pipeline.setTrackingMode(selectedMode)
        renderTrackingMode()
        resetPositionCalibration()
    }

    private func configureFramingButton() {
        framingButton.accessibilityIdentifier = "setup.wide"
        framingButton.accessibilityLabel = "Wide camera view".rdLocalized
        framingButton.accessibilityHint = "Uses the wider front camera field of view when available.".rdLocalized
        framingButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        framingButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        framingButton.addAction(UIAction { [weak self] _ in self?.toggleFramingMode() }, for: .touchUpInside)
        renderFramingButton()
    }

    private func renderFramingButton() {
        let isAvailable = pipeline.isWideFramingAvailable
        let isWide = framingMode == .wide && isAvailable
        var configuration = UIButton.Configuration.plain()
        configuration.cornerStyle = .capsule
        configuration.title = (isAvailable ? "WIDE" : "WIDE · N/A").rdLocalized
        configuration.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        configuration.imagePadding = 6
        configuration.background.backgroundColor = isWide ? RDColor.accent : .clear
        configuration.background.strokeColor = isAvailable ? RDColor.accent : RDColor.separator
        configuration.background.strokeWidth = 1.5
        configuration.baseForegroundColor = isWide ? RDColor.background : (isAvailable ? RDColor.accent : RDColor.tertiaryLabel)
        framingButton.configuration = configuration
        framingButton.isEnabled = isAvailable && !isChangingFramingMode
        framingButton.isSelected = isWide
        framingButton.accessibilityValue = (isAvailable ? (isWide ? "On" : "Off") : "Unavailable").rdLocalized
        framingButton.accessibilityTraits = isWide ? [.button, .selected] : .button
    }

    private func toggleFramingMode() {
        guard pipeline.isWideFramingAvailable, !isChangingFramingMode else { return }
        let requestedMode: CameraFramingMode = framingMode == .wide ? .standard : .wide
        isChangingFramingMode = true
        renderFramingButton()
        pipeline.setFramingMode(requestedMode) { [weak self] result in
            guard let self else { return }
            self.isChangingFramingMode = false
            switch result {
            case let .success(activeMode):
                self.framingMode = activeMode
                self.preferences.prefersWideCamera = activeMode == .wide
                self.resetPositionCalibrationAfterFramingChange()
            case let .failure(error):
                self.statusLabel.text = "Could not change the camera view: %@".rdLocalizedFormat(error.localizedDescription)
            }
            self.renderFramingButton()
        }
    }

    private func resetPositionCalibrationAfterFramingChange() {
        resetPositionCalibration()
    }

    private func resetPositionCalibration() {
        guard cameraAccess.state == .authorized else {
            enterDemoReadyState()
            return
        }
        stableSince = nil
        isPositionLocked = false
        isCompletingWithGesture = false
        gestureDetector.reset()
        gestureCompletionWorkItem?.cancel()
        gestureCompletionWorkItem = nil
        progressView.setProgress(0, animated: false)
        continueButton.isEnabled = false
        continueButton.configuration?.title = "HOLD YOUR POSITION".rdLocalized
        continueButton.configuration?.image = nil
        statusLabel.text = framingMode == .wide
            ? "Wide view enabled. Keep the required joints inside the guide.".rdLocalized
            : trackingMode.instruction(for: exercise)
    }

    private func consume(_ frame: PoseFrame) {
        guideOverlay.update(frame: frame)
        guard !isCompletingWithGesture, !hasContinued else { return }
        let framing = PoseFramingEvaluator.evaluate(
            exercise: exercise,
            frame: frame,
            trackingMode: trackingMode
        )
        statusLabel.text = framing.guidance
        if framing.isReady {
            if stableSince == nil { stableSince = Date() }
            let elapsed = Date().timeIntervalSince(stableSince ?? Date())
            progressView.setProgress(Float(min(1, elapsed / requiredStableDuration)), animated: true)
            if elapsed >= requiredStableDuration { markReady() }
            if isPositionLocked {
                statusLabel.text = "Position locked. Raise one hand to continue.".rdLocalized
                if gestureDetector.update(frame: frame) {
                    confirmWithGesture()
                }
            }
        } else {
            isPositionLocked = false
            gestureDetector.reset()
            stableSince = nil
            continueButton.isEnabled = false
            continueButton.configuration?.title = "HOLD YOUR POSITION".rdLocalized
            progressView.setProgress(0, animated: true)
        }
    }

    private func markReady() {
        guard !isPositionLocked else { return }
        isPositionLocked = true
        continueButton.isEnabled = true
        continueButton.configuration?.title = "POSITION LOCKED · CONTINUE".rdLocalized
        continueButton.configuration?.image = nil
        continueButton.configuration?.imagePadding = 8
        statusLabel.text = "Position locked. Raise one hand to continue.".rdLocalized
        UIAccessibility.post(
            notification: .announcement,
            argument: "Position locked. Raise one hand and hold briefly to continue.".rdLocalized
        )
    }

    private func confirmWithGesture() {
        guard !isCompletingWithGesture, !hasContinued else { return }
        isCompletingWithGesture = true
        continueButton.isEnabled = false
        continueButton.configuration?.title = "GESTURE CONFIRMED".rdLocalized
        continueButton.configuration?.image = UIImage(systemName: "checkmark.circle.fill")
        statusLabel.text = "Gesture confirmed. Put your hand back down.".rdLocalized
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIAccessibility.post(
            notification: .announcement,
            argument: "Gesture confirmed. Put your hand back down.".rdLocalized
        )

        let workItem = DispatchWorkItem { [weak self] in self?.continueNow() }
        gestureCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func continueNow() {
        guard !hasContinued else { return }
        hasContinued = true
        gestureCompletionWorkItem?.cancel()
        gestureCompletionWorkItem = nil
        onContinue?()
    }

    private func enterDemoReadyState() {
        progressView.progress = 1
        markReady()
        statusLabel.text = "Demo mode uses a reference image. Live tracking requires a physical iPhone camera.".rdLocalized
    }

    private func confirmManualContinue() {
        let alert = UIAlertController(
            title: "Continue without calibration?".rdLocalized,
            message: "Poor camera placement can reduce counting accuracy.".rdLocalized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Keep adjusting".rdLocalized, style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue".rdLocalized, style: .default) { [weak self] _ in self?.continueNow() })
        present(alert, animated: true)
    }

    private func showCameraError(_ error: Error) {
        fallbackImageView.isHidden = false
        statusLabel.text = "Camera unavailable: %@".rdLocalizedFormat(error.localizedDescription)
        continueButton.isEnabled = true
        continueButton.configuration?.title = "CONTINUE IN DEMO MODE".rdLocalized
    }

    private func render(cameraState: CameraRuntimeState) {
        switch cameraState {
        case .idle, .configuring:
            statusLabel.text = "Starting the on-device camera…".rdLocalized
        case .running, .stopped:
            break
        case let .interrupted(message), let .failed(message):
            isPositionLocked = false
            stableSince = nil
            continueButton.isEnabled = false
            statusLabel.text = message
        }
    }
}
