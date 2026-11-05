import UIKit

/// Recovery screen shown when camera access was denied. Returning from
/// Settings with access granted continues automatically.
final class CameraPermissionViewController: RDBaseViewController {
    private let service: CameraAuthorizationService
    private var activeObserver: NSObjectProtocol?
    var onContinue: (() -> Void)?

    init(service: CameraAuthorizationService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = RDPrimaryButton(title: "OPEN SETTINGS", symbolName: "arrow.up.right")
        button.accessibilityIdentifier = "cameraPermission.settings"
        button.addAction(UIAction { [weak self] _ in self?.service.openSystemSettings() }, for: .touchUpInside)
        let (_, stack) = makeScrollableContent(pinnedFooter: makeFooter([button]))

        let iconBox = UIView()
        iconBox.backgroundColor = RDColor.warning.withAlphaComponent(0.12)
        iconBox.layer.cornerRadius = 48
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(
            systemName: "video.slash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 38, weight: .medium)
        ))
        icon.tintColor = RDColor.warning
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 96),
            iconBox.heightAnchor.constraint(equalToConstant: 96),
            icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor)
        ])
        let iconRow = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [iconBox, UIView()])

        let eyebrow = makeEyebrow("CAMERA OFF · CAMERA ACCESS IS OFF", color: RDColor.warning)
        let title = makeLabel(text: "LET REPDUO\nSEE THE MOVE.", font: RDFont.display(42))
        title.accessibilityTraits = .header
        let body = makeLabel(
            text: "Counting and AI scoring need the camera. Frames are processed on this iPhone and never recorded.",
            font: RDFont.body(),
            color: RDColor.textSecondary
        )

        let steps = makeCard()
        let stepsStack = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [
            step(1, "Tap Open Settings below"),
            step(2, "Turn on Camera"),
            step(3, "Come back to RepDuo to continue")
        ])
        steps.addSubview(stepsStack)
        stepsStack.pinEdges(to: steps, insets: NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

        [iconRow, eyebrow, title, body, steps].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(8, after: eyebrow)
        stack.setCustomSpacing(12, after: title)

        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.service.state == .authorized else { return }
            self.onContinue?()
        }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    private func step(_ number: Int, _ text: String) -> UIView {
        let numberLabel = UILabel()
        numberLabel.text = String(number)
        numberLabel.font = RDFont.numeric(26)
        numberLabel.textColor = RDColor.neonGreen
        numberLabel.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let label = makeLabel(text: text, font: RDFont.body(weight: .medium))
        let row = UIStackView(axis: .horizontal, spacing: 14, arrangedSubviews: [numberLabel, label])
        row.alignment = .center
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        return row
    }
}
