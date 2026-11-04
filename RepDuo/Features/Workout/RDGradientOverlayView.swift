import UIKit

final class RDGradientOverlayView: UIView {
    enum Direction { case top, bottom, both }
    var direction: Direction = .both { didSet { updateColors() } }
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityAppearanceChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func updateColors() {
        let opaque = RDColor.camera.withAlphaComponent(0.96).cgColor
        let clearAlpha: CGFloat = UIAccessibility.isReduceTransparencyEnabled ? 0.58 : 0
        let clear = RDColor.camera.withAlphaComponent(clearAlpha).cgColor
        switch direction {
        case .top:
            gradient.colors = [opaque, clear]
            gradient.locations = [0, 1]
        case .bottom:
            gradient.colors = [clear, opaque]
            gradient.locations = [0, 1]
        case .both:
            gradient.colors = [opaque, clear, clear, opaque]
            gradient.locations = [0, 0.28, 0.62, 1]
        }
    }

    @objc private func accessibilityAppearanceChanged() {
        updateColors()
    }
}
