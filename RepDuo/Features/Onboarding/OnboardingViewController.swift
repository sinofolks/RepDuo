import UIKit

final class OnboardingViewController: RDBaseViewController {
    var onContinue: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        let (_, stack) = makeScrollableContent()
        stack.spacing = RDSpacing.xl

        let wordmark = RDWordmarkView()
        let eyebrow = makeLabel(
            text: "CAMERA-POWERED FORM TRACKING",
            font: .systemFont(ofSize: 12, weight: .bold),
            color: RDColor.neonGreen
        )
        eyebrow.accessibilityTraits = .header
        let title = makeLabel(text: "TWO MOVES.\nONE FOCUS.", font: RDFont.display(48))
        title.accessibilityTraits = .header
        let body = makeLabel(
            text: "RepDuo counts every squat and push-up while you train—without wearables, accounts, or uploads.",
            font: RDFont.body(),
            color: RDColor.textSecondary
        )

        let privacy = makePrivacyPanel()
        let getStarted = RDPrimaryButton(title: "GET STARTED", symbolName: "arrow.right")
        getStarted.accessibilityIdentifier = "onboarding.getStarted"
        getStarted.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)

        [wordmark, spacer(20), eyebrow, title, body, spacer(16), privacy, getStarted].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(2, after: eyebrow)
        stack.setCustomSpacing(RDSpacing.md, after: title)
    }

    private func makePrivacyPanel() -> UIView {
        let panel = UIView()
        panel.backgroundColor = RDColor.surface
        panel.layer.cornerRadius = RDCornerRadius.medium
        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        icon.tintColor = RDColor.neonGreen
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = makeLabel(text: "PRIVATE BY DESIGN", font: RDFont.caption())
        let body = makeLabel(
            text: "Camera processing happens on this iPhone. Video is never saved or uploaded.",
            font: RDFont.caption(weight: .regular),
            color: RDColor.textSecondary
        )
        let labels = UIStackView(axis: .vertical, spacing: 5, arrangedSubviews: [title, body])
        panel.addSubview(icon)
        panel.addSubview(labels)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            labels.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            labels.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16)
        ])
        panel.isAccessibilityElement = true
        panel.accessibilityLabel = "Private by design. Camera processing happens on this iPhone. Video is never saved or uploaded.".rdLocalized
        return panel
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
