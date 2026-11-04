import UIKit

final class CountdownViewController: RDBaseViewController {
    private let exercise: ExerciseType
    private let pipeline: CameraVisionPipeline
    private let cameraAccess: CameraAuthorizationService
    private let feedback: FeedbackService
    private let cameraView = NeonCameraView()
    private let fallbackImageView = UIImageView()
    private let numberLabel = RDNumberLabel()
    private let statusLabel = UILabel()
    private let ring = RDRingView()
    private var remaining = 3
    private var timer: Timer?
    private var bodyAvailable = false
    private var lastValidPoseReceivedAt: TimeInterval?

    var onComplete: (() -> Void)?

    init(
        exercise: ExerciseType,
        pipeline: CameraVisionPipeline,
        cameraAccess: CameraAuthorizationService,
        feedback: FeedbackService
    ) {
        self.exercise = exercise
        self.pipeline = pipeline
        self.cameraAccess = cameraAccess
        self.feedback = feedback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        useCameraStageAppearance()
        fallbackImageView.image = UIImage(named: exercise.demoImageName)
        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.clipsToBounds = true
        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        view.addSubview(fallbackImageView)
        cameraView.pinEdges(to: view)
        fallbackImageView.pinEdges(to: view)
        fallbackImageView.isHidden = cameraAccess.state == .authorized
        if cameraAccess.state == .authorized { pipeline.attach(renderView: cameraView) }
        else { bodyAvailable = true }

        let shade = UIView()
        shade.backgroundColor = RDColor.camera.withAlphaComponent(0.62)
        view.addSubview(shade)
        shade.pinEdges(to: view)

        numberLabel.text = String(remaining)
        numberLabel.textColor = RDColor.accent
        numberLabel.font = RDFont.numeric(180, maximumScale: 1)
        numberLabel.adjustsFontSizeToFitWidth = true
        numberLabel.minimumScaleFactor = 0.5
        numberLabel.textAlignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.accessibilityIdentifier = "countdown.number"
        numberLabel.layer.shadowColor = RDColor.accent.cgColor
        numberLabel.layer.shadowRadius = 24
        numberLabel.layer.shadowOpacity = 0.55
        numberLabel.layer.shadowOffset = .zero
        ring.lineWidth = 10
        ring.setProgress(1, animated: false)
        statusLabel.text = "HOLD YOUR POSITION".rdLocalized
        statusLabel.textColor = RDColor.label
        statusLabel.font = RDFont.title(22)
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let hint = makeLabel(
            text: "Leaving the frame pauses the countdown",
            font: RDFont.caption(weight: .regular),
            color: RDColor.secondaryLabel
        )
        hint.textAlignment = .center
        let title = makeEyebrow("GET READY · %@".rdLocalizedFormat(exercise.displayName))
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        let skip = UIButton(type: .system)
        var skipConfiguration = UIButton.Configuration.filled()
        skipConfiguration.title = "SKIP COUNTDOWN".rdLocalized
        skipConfiguration.cornerStyle = .capsule
        skipConfiguration.baseBackgroundColor = RDColor.label.withAlphaComponent(0.08)
        skipConfiguration.baseForegroundColor = RDColor.label
        skipConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        skip.configuration = skipConfiguration
        skip.accessibilityIdentifier = "countdown.skip"
        skip.addAction(UIAction { [weak self] _ in self?.finish() }, for: .touchUpInside)
        let bottom = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [statusLabel, hint, skip])
        bottom.alignment = .center
        bottom.setCustomSpacing(28, after: hint)
        [title, ring, numberLabel, bottom].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: RDSpacing.lg),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ring.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            ring.widthAnchor.constraint(equalTo: ring.heightAnchor),
            ring.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.76).withPriority(.defaultHigh),
            ring.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.55),
            numberLabel.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            numberLabel.widthAnchor.constraint(equalTo: ring.widthAnchor, multiplier: 0.7),
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: RDLayout.screenMargin),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -RDLayout.screenMargin),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -RDSpacing.lg)
        ])

        pipeline.onPoseFrame = { [weak self] frame in
            self?.bodyAvailable = frame.quality.permitsCounting
            self?.lastValidPoseReceivedAt = frame.quality.permitsCounting
                ? ProcessInfo.processInfo.systemUptime
                : nil
            self?.statusLabel.text = frame.quality.permitsCounting ? "HOLD YOUR POSITION".rdLocalized : frame.quality.message
        }
        pipeline.onCameraStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .running: break
            case let .interrupted(message), let .failed(message):
                self.bodyAvailable = false
                self.lastValidPoseReceivedAt = nil
                self.statusLabel.text = message
            case .idle, .configuring, .stopped:
                break
            }
        }
        pipeline.onError = { [weak self] error in
            self?.bodyAvailable = false
            self?.lastValidPoseReceivedAt = nil
            self?.statusLabel.text = error.localizedDescription
        }
        feedback.countdown(remaining)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    deinit { timer?.invalidate() }

    private var hasFinished = false

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        timer?.invalidate()
        onComplete?()
    }

    @objc private func tick() {
        let recentlyValid = lastValidPoseReceivedAt.map {
            ProcessInfo.processInfo.systemUptime - $0 <= 0.5
        } ?? false
        guard cameraAccess.state != .authorized || (bodyAvailable && recentlyValid) else {
            statusLabel.text = "COUNTDOWN PAUSED — STEP BACK IN FRAME".rdLocalized
            return
        }
        remaining -= 1
        feedback.countdown(remaining)
        ring.setProgress(CGFloat(remaining) / 3, animated: true)
        if remaining <= 0 {
            timer?.invalidate()
            numberLabel.text = "GO".rdLocalized
            UIView.animate(withDuration: 0.22, animations: {
                self.numberLabel.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                self.numberLabel.alpha = 0.7
            }) { [weak self] _ in self?.finish() }
        } else {
            numberLabel.text = String(remaining)
            numberLabel.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            UIView.animate(withDuration: 0.24) { self.numberLabel.transform = .identity }
        }
    }
}
