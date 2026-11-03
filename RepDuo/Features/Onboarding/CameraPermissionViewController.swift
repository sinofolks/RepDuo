import UIKit

final class CameraPermissionViewController: RDBaseViewController {
    enum Mode { case rationale, denied }

    private let mode: Mode
    private let service: CameraAuthorizationService
    private var activeObserver: NSObjectProtocol?
    var onContinue: (() -> Void)?
    var onDenied: (() -> Void)?

    init(mode: Mode, service: CameraAuthorizationService) {
        self.mode = mode
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = mode == .rationale
        let (_, stack) = makeScrollableContent()

        let wordmark = RDWordmarkView()
        let icon = UIImageView(image: UIImage(systemName: mode == .rationale ? "camera.viewfinder" : "camera.badge.ellipsis"))
        icon.tintColor = mode == .rationale ? RDColor.neonGreen : RDColor.warning
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let eyebrow = makeLabel(
            text: mode == .rationale ? "ONE REQUIRED PERMISSION" : "CAMERA ACCESS IS OFF",
            font: RDFont.caption(),
            color: mode == .rationale ? RDColor.neonGreen : RDColor.warning
        )
        let title = makeLabel(
            text: mode == .rationale ? "YOUR CAMERA.\nYOUR DATA." : "LET REPDUO\nSEE THE MOVE.",
            font: RDFont.display(42)
        )
        title.accessibilityTraits = .header
        let body = makeLabel(
            text: mode == .rationale
                ? "RepDuo needs the camera to see your body position, identify each movement phase, and count a complete rep."
                : "Enable Camera in Settings to use live tracking. Your video stays on this iPhone and is never recorded.",
            font: RDFont.body(),
            color: RDColor.textSecondary
        )

        let facts = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [
            fact(symbol: "iphone", text: "On-device processing"),
            fact(symbol: "video.slash", text: "No video recording"),
            fact(symbol: "icloud.slash", text: "No camera upload")
        ])

        let buttonTitle = mode == .rationale ? primaryTitle : "OPEN SETTINGS"
        let button = RDPrimaryButton(title: buttonTitle, symbolName: mode == .rationale ? "camera.fill" : "gear")
        button.accessibilityIdentifier = mode == .rationale ? "cameraPermission.continue" : "cameraPermission.settings"
        button.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)

        [wordmark, icon, eyebrow, title, body, facts, button].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(2, after: eyebrow)
        if mode == .denied {
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.service.state == .authorized else { return }
                self.onContinue?()
            }
        }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    private var primaryTitle: String {
        switch service.state {
        case .unavailable: return "CONTINUE IN DEMO MODE"
        case .authorized: return "CONTINUE"
        case .notDetermined, .denied: return "ALLOW CAMERA"
        }
    }

    private func primaryTapped() {
        if mode == .denied {
            service.openSystemSettings()
            return
        }
        switch service.state {
        case .authorized, .unavailable:
            onContinue?()
        case .notDetermined:
            service.request { [weak self] state in
                if state == .authorized || state == .unavailable { self?.onContinue?() }
                else { self?.onDenied?() }
            }
        case .denied:
            onDenied?()
        }
    }

    private func fact(symbol: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = RDColor.neonGreen
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let label = makeLabel(text: text, font: RDFont.body(weight: .semibold))
        let row = UIStackView(axis: .horizontal, spacing: 14, arrangedSubviews: [icon, label])
        row.alignment = .center
        return row
    }
}
