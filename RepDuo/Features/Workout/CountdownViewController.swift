import UIKit

final class CountdownViewController: RDBaseViewController {
    private let exercise: ExerciseType
    private let pipeline: CameraVisionPipeline
    private let cameraAccess: CameraAuthorizationService
    private let feedback: FeedbackService
    private let cameraView = NeonCameraView()
    private let fallbackImageView = UIImageView()
    private let numberLabel = UILabel()
    private let statusLabel = UILabel()
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
        shade.backgroundColor = RDColor.background.withAlphaComponent(0.58)
        view.addSubview(shade)
        shade.pinEdges(to: view)

        numberLabel.text = String(remaining)
        numberLabel.textColor = RDColor.neonGreen
        numberLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 128, weight: .black),
            maximumPointSize: 160
        )
        numberLabel.adjustsFontForContentSizeCategory = true
        numberLabel.adjustsFontSizeToFitWidth = true
        numberLabel.textAlignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.accessibilityIdentifier = "countdown.number"
        statusLabel.text = "HOLD YOUR POSITION".rdLocalized
        statusLabel.textColor = RDColor.warmWhite
        statusLabel.font = .systemFont(ofSize: 16, weight: .bold)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel(text: exercise.displayName, font: RDFont.caption(), color: RDColor.warmWhite)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)
        view.addSubview(numberLabel)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: RDSpacing.xl),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            numberLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            numberLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
            statusLabel.topAnchor.constraint(equalTo: numberLabel.bottomAnchor, constant: RDSpacing.lg),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        pipeline.onPoseFrame = { [weak self] frame in
            self?.bodyAvailable = frame.quality.permitsCounting
            self?.lastValidPoseReceivedAt = frame.quality.permitsCounting
                ? ProcessInfo.processInfo.systemUptime
                : nil
            self?.statusLabel.text = frame.quality.permitsCounting ? "HOLD YOUR POSITION".rdLocalized : frame.quality.message.uppercased()
        }
        pipeline.onCameraStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .running: break
            case let .interrupted(message), let .failed(message):
                self.bodyAvailable = false
                self.lastValidPoseReceivedAt = nil
                self.statusLabel.text = message.uppercased()
            case .idle, .configuring, .stopped:
                break
            }
        }
        pipeline.onError = { [weak self] error in
            self?.bodyAvailable = false
            self?.lastValidPoseReceivedAt = nil
            self?.statusLabel.text = error.localizedDescription.uppercased()
        }
        feedback.countdown(remaining)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    deinit { timer?.invalidate() }

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
        if remaining <= 0 {
            timer?.invalidate()
            numberLabel.text = "GO".rdLocalized
            UIView.animate(withDuration: 0.22, animations: {
                self.numberLabel.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                self.numberLabel.alpha = 0.7
            }) { [weak self] _ in self?.onComplete?() }
        } else {
            numberLabel.text = String(remaining)
            numberLabel.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            UIView.animate(withDuration: 0.24) { self.numberLabel.transform = .identity }
        }
    }
}
