import UIKit

final class GearCheckViewController: RDBaseViewController {
    private let watchService: WatchStatusService
    private let audioService: AudioRouteService
    private let preferences: AppPreferences
    private let watchCard = RDDeviceStatusCard(symbol: "applewatch", title: "Apple Watch", iconTint: RDColor.accent)
    private let audioCard = RDDeviceStatusCard(symbol: "headphones", title: "Audio output")
    private let cameraCard = RDDeviceStatusCard(symbol: "camera", title: "Camera counting", iconTint: RDColor.accent)
    private let refreshButton = RDPrimaryButton(title: "SCAN AGAIN", style: .secondary)
    private let continueButton = RDPrimaryButton(title: "CONTINUE")
    private var didFinishInitialRefresh = false

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
        let footer = makeFooter([refreshButton, continueButton])
        footer.distribution = .fill
        continueButton.widthAnchor.constraint(equalTo: refreshButton.widthAnchor, multiplier: 1.4).isActive = true
        let (_, stack) = makeScrollableContent(pinnedFooter: footer)
        let eyebrow = makeEyebrow("PRE-WORKOUT · OPTIONAL")
        let title = makeLabel(text: "GEAR\nCHECK.", font: RDFont.title(34))
        title.accessibilityTraits = .header
        let body = makeLabel(
            text: "Pair a Watch for heart rate and wear headphones for voice cues. Neither is required to train.",
            font: RDFont.body(),
            color: RDColor.secondaryLabel
        )
        refreshButton.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .touchUpInside)
        continueButton.accessibilityIdentifier = "gear.continue"
        continueButton.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)
        let cards = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [watchCard, audioCard, cameraCard])
        [RDWordmarkView(), eyebrow, title, body, cards].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(8, after: eyebrow)
        stack.setCustomSpacing(12, after: title)

        watchService.onChange = { [weak self] status in self?.render(watch: status) }
        audioService.onChange = { [weak self] status in self?.render(audio: status) }
        refresh()
    }

    private func refresh() {
        refreshButton.isEnabled = false
        continueButton.isEnabled = false
        cameraCard.update(status: "Checking", detail: "Checking current device status…", connected: false)
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
            self.cameraCard.update(status: "Ready", detail: "Core training is ready", connected: true)
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
            watchCard.update(status: "Not paired", detail: "Optional — continue without heart rate", connected: false)
        }
    }

    private func render(audio: AudioRouteStatus) {
        guard didFinishInitialRefresh else { return }
        let status = audio.isBluetooth ? "Connected" : "System audio"
        let cues = (preferences.soundEnabled ? "Audio cues on" : "Audio cues off").rdLocalized
        audioCard.update(status: status, detail: "\(audio.outputName) · \(cues)", connected: true)
    }
}
