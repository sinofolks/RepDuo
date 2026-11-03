import UIKit

final class GearCheckViewController: RDBaseViewController {
    private let watchService: WatchStatusService
    private let audioService: AudioRouteService
    private let preferences: AppPreferences
    private let watchCard = RDDeviceStatusCard(symbol: "applewatch", title: "Apple Watch")
    private let audioCard = RDDeviceStatusCard(symbol: "headphones", title: "Audio output")
    private let stateLabel = UILabel()
    private let refreshButton = RDPrimaryButton(title: "SCAN AGAIN", style: .secondary)
    private let continueButton = RDPrimaryButton(title: "READY TO TRAIN", symbolName: "arrow.right")
    private lazy var actionsStack: UIStackView = {
        let stack = UIStackView(
            axis: .vertical,
            spacing: RDSpacing.sm,
            arrangedSubviews: [refreshButton, continueButton]
        )
        stack.distribution = .fillEqually
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: RDSpacing.sm,
            leading: RDSpacing.lg,
            bottom: RDSpacing.sm,
            trailing: RDSpacing.lg
        )
        stack.backgroundColor = RDColor.background
        return stack
    }()
    private var didFinishInitialRefresh = false
    private var usesCompactHeightLayout = false

    var onContinue: (() -> Void)?

    init(watchService: WatchStatusService, audioService: AudioRouteService, preferences: AppPreferences) {
        self.watchService = watchService
        self.audioService = audioService
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        let (_, stack) = makeScrollableContent(pinnedFooter: actionsStack)
        let wordmark = RDWordmarkView()
        let eyebrow = makeLabel(text: "PRE-WORKOUT CHECK", font: RDFont.caption(), color: RDColor.neonGreen)
        let title = makeLabel(text: "GEAR\nCHECK.", font: RDFont.display(44))
        title.accessibilityTraits = .header
        let body = makeLabel(
            text: "Optional devices add heart-rate tracking and private audio cues. They never block your workout.",
            font: RDFont.body(),
            color: RDColor.textSecondary
        )
        stateLabel.font = RDFont.caption()
        stateLabel.textColor = RDColor.neonGreen
        stateLabel.numberOfLines = 0
        stateLabel.adjustsFontForContentSizeCategory = true
        refreshButton.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .touchUpInside)
        continueButton.accessibilityIdentifier = "gear.continue"
        continueButton.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)
        [wordmark, eyebrow, title, body, watchCard, audioCard, stateLabel].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(2, after: eyebrow)

        watchService.onChange = { [weak self] status in self?.render(watch: status) }
        audioService.onChange = { [weak self] status in self?.render(audio: status) }
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateResponsiveLayout()
    }

    private func updateResponsiveLayout() {
        let shouldUseCompactHeightLayout = view.bounds.width > view.bounds.height
        guard shouldUseCompactHeightLayout != usesCompactHeightLayout else { return }
        usesCompactHeightLayout = shouldUseCompactHeightLayout
        actionsStack.axis = shouldUseCompactHeightLayout ? .horizontal : .vertical
        actionsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: RDSpacing.sm,
            leading: shouldUseCompactHeightLayout ? RDSpacing.md : RDSpacing.lg,
            bottom: RDSpacing.sm,
            trailing: shouldUseCompactHeightLayout ? RDSpacing.md : RDSpacing.lg
        )
    }

    private func refresh() {
        refreshButton.isEnabled = false
        continueButton.isEnabled = false
        stateLabel.text = "●  CHECKING CURRENT DEVICE STATUS…".rdLocalized
        watchCard.update(status: "Checking", detail: "Reading paired Watch state", connected: false)
        audioCard.update(status: "Checking", detail: "Reading current system audio route", connected: false)
        watchService.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.didFinishInitialRefresh = true
            self.render(watch: self.watchService.currentStatus)
            self.render(audio: self.audioService.currentStatus)
            self.refreshButton.isEnabled = true
            self.continueButton.isEnabled = true
            self.stateLabel.text = "●  CORE TRAINING IS READY".rdLocalized
        }
    }

    private func render(watch: WatchStatus) {
        guard didFinishInitialRefresh else { return }
        switch watch.availability {
        case .reachable:
            watchCard.update(status: "Connected", detail: "Companion installed · reachable now", connected: true)
        case .pairedUnavailable:
            watchCard.update(status: "Paired", detail: "Companion installed · currently unavailable", connected: true)
        case .companionNotInstalled:
            watchCard.update(status: "Paired", detail: "Companion not installed · optional", connected: true)
        case .notPaired:
            watchCard.update(status: "Unavailable", detail: "Optional — continue without heart rate", connected: false)
        }
    }

    private func render(audio: AudioRouteStatus) {
        guard didFinishInitialRefresh else { return }
        let status = audio.isBluetooth ? "Connected" : "System audio"
        let cues = (preferences.soundEnabled ? "Audio cues on" : "Audio cues off").rdLocalized
        audioCard.update(status: status, detail: "\(audio.outputName) · \(cues)", connected: true)
    }
}
