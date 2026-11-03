import UIKit

final class RDPrimaryButton: UIButton {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    private let style: Style

    init(title: String, style: Style = .primary, symbolName: String? = nil) {
        self.style = style
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title.rdLocalized
        configuration.image = symbolName.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 12
        configuration.imagePlacement = .leading
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 17, leading: 22, bottom: 17, trailing: 22)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
                for: .systemFont(ofSize: 16, weight: .bold),
                maximumPointSize: 22
            )
            return outgoing
        }
        self.configuration = configuration
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        accessibilityTraits.insert(.button)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override var isEnabled: Bool {
        didSet { updateColors() }
    }

    private func updateColors() {
        var configuration = configuration
        switch style {
        case .primary:
            configuration?.baseBackgroundColor = isEnabled ? RDColor.neonGreen : RDColor.surfaceSecondary
            configuration?.baseForegroundColor = isEnabled ? RDColor.backgroundDeep : RDColor.textMuted
        case .secondary:
            configuration?.baseBackgroundColor = .clear
            configuration?.baseForegroundColor = isEnabled ? RDColor.warmWhite : RDColor.textMuted
            configuration?.background.strokeColor = isEnabled ? RDColor.textSecondary : RDColor.separatorOnDark
            configuration?.background.strokeWidth = 1.5
        case .destructive:
            configuration?.baseBackgroundColor = RDColor.destructive.withAlphaComponent(isEnabled ? 0.16 : 0.08)
            configuration?.baseForegroundColor = isEnabled ? RDColor.destructive : RDColor.textMuted
        }
        self.configuration = configuration
    }
}

private final class RDLogoMarkView: UIView {
    enum Surface {
        case dark
        case light
    }

    private let leadingColor: UIColor

    init(surface: Surface) {
        leadingColor = surface == .dark ? RDColor.warmWhite : RDColor.background
        super.init(frame: .zero)
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), rect.width > 0, rect.height > 0 else { return }
        let referenceSize = CGSize(width: 64, height: 32)
        let scale = min(rect.width / referenceSize.width, rect.height / referenceSize.height)
        let offset = CGPoint(
            x: (rect.width - referenceSize.width * scale) / 2,
            y: (rect.height - referenceSize.height * scale) / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(6 * scale)

        context.beginPath()
        context.move(to: point(4, 25))
        context.addLine(to: point(22, 25))
        context.addLine(to: point(38, 6))
        context.setStrokeColor(leadingColor.cgColor)
        context.strokePath()

        context.beginPath()
        context.move(to: point(38, 6))
        context.addCurve(
            to: point(49, 8),
            control1: point(41, 2.5),
            control2: point(46, 3)
        )
        context.addLine(to: point(60, 25))
        context.setStrokeColor(RDColor.neonGreen.cgColor)
        context.strokePath()
    }
}

final class RDWordmarkView: UIView {
    enum Surface {
        case dark
        case light
    }

    init(surface: Surface = .dark) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = "RepDuo"
        let mark = RDLogoMarkView(surface: surface == .dark ? .dark : .light)
        let wordmark = UILabel()
        wordmark.text = "RepDuo"
        wordmark.textColor = surface == .dark ? RDColor.warmWhite : RDColor.background
        wordmark.font = .systemFont(ofSize: 24, weight: .black)
        wordmark.adjustsFontSizeToFitWidth = true
        wordmark.minimumScaleFactor = 0.9
        wordmark.setContentCompressionResistancePriority(.required, for: .horizontal)
        wordmark.isAccessibilityElement = false

        let content = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [mark, wordmark])
        content.alignment = .center
        content.isUserInteractionEnabled = false
        addSubview(content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 156),
            heightAnchor.constraint(equalToConstant: 48),
            mark.widthAnchor.constraint(equalToConstant: 50),
            mark.heightAnchor.constraint(equalToConstant: 28),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class RDStatusPill: UIView {
    private let dot = UIView()
    private let label = UILabel()

    init(text: String, positive: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.surface
        layer.cornerRadius = 14

        dot.backgroundColor = positive ? RDColor.neonGreen : RDColor.warning
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.text = text.rdLocalized.uppercased()
        label.textColor = positive ? RDColor.neonGreen : RDColor.warning
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class RDDeviceStatusCard: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.surface
        layer.cornerRadius = RDCornerRadius.medium
        layer.borderColor = RDColor.separatorOnDark.cgColor
        layer.borderWidth = 1

        let iconBox = UIView()
        iconBox.backgroundColor = RDColor.warmWhite
        iconBox.layer.cornerRadius = 14
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = RDColor.background
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)

        titleLabel.text = title.rdLocalized.uppercased()
        titleLabel.textColor = RDColor.warmWhite
        titleLabel.font = RDFont.body(weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        statusLabel.font = .systemFont(ofSize: 12, weight: .bold)
        detailLabel.textColor = RDColor.textSecondary
        detailLabel.font = RDFont.caption(weight: .regular)
        detailLabel.numberOfLines = 0

        let labels = UIStackView(axis: .vertical, spacing: 5, arrangedSubviews: [titleLabel, statusLabel, detailLabel])
        addSubview(iconBox)
        addSubview(labels)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 116),
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 64),
            iconBox.heightAnchor.constraint(equalToConstant: 64),
            iconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 16),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(status: String, detail: String, connected: Bool) {
        let localizedStatus = status.rdLocalized
        let localizedDetail = detail.rdLocalized
        statusLabel.text = "●  \(localizedStatus.uppercased())"
        statusLabel.textColor = connected ? RDColor.neonGreen : RDColor.warning
        detailLabel.text = localizedDetail
        accessibilityLabel = "%1$@, %2$@, %3$@".rdLocalizedFormat(
            titleLabel.text ?? "Device".rdLocalized,
            localizedStatus,
            localizedDetail
        )
    }
}

final class RDExerciseCard: UIControl {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let selectionLabel = UILabel()

    let exercise: ExerciseType

    init(exercise: ExerciseType) {
        self.exercise = exercise
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = RDCornerRadius.large
        layer.borderWidth = 1.5

        symbolView.image = UIImage(systemName: exercise.symbolName)
        symbolView.contentMode = .scaleAspectFit
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = exercise.displayName
        titleLabel.font = RDFont.title(24)
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.text = (exercise == .squat ? "STAND · DROP · DRIVE" : "PLANK · LOWER · PRESS").rdLocalized
        detailLabel.font = RDFont.caption(weight: .bold)
        detailLabel.numberOfLines = 2
        selectionLabel.text = "SELECTED".rdLocalized
        selectionLabel.font = .systemFont(ofSize: 10, weight: .black)
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [selectionLabel, symbolView, titleLabel, detailLabel])
        stack.alignment = .leading
        // Keep the whole visible card as one hit target. Otherwise the layout
        // stack can win hit-testing and prevent this UIControl from receiving
        // touchUpInside when users tap its labels or symbol.
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -18),
            symbolView.widthAnchor.constraint(equalToConstant: 68),
            symbolView.heightAnchor.constraint(equalToConstant: 68)
        ])
        accessibilityLabel = exercise.displayName
        accessibilityTraits = .button
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : 1 }
    }

    private func updateAppearance() {
        backgroundColor = isSelected ? RDColor.neonGreen : RDColor.surface
        layer.borderColor = (isSelected ? RDColor.neonGreen : RDColor.separatorOnDark).cgColor
        let foreground = isSelected ? RDColor.backgroundDeep : RDColor.warmWhite
        titleLabel.textColor = foreground
        symbolView.tintColor = foreground
        detailLabel.textColor = isSelected ? RDColor.background.withAlphaComponent(0.72) : RDColor.textSecondary
        selectionLabel.textColor = foreground
        selectionLabel.isHidden = !isSelected
        accessibilityValue = (isSelected ? "Selected" : "Not selected").rdLocalized
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

final class RDSummaryMetricRow: UIView {
    init(label: String, value: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let labelView = UILabel()
        let localizedLabel = label.rdLocalized
        labelView.text = localizedLabel.uppercased()
        labelView.textColor = RDColor.textMuted
        labelView.font = .systemFont(ofSize: 12, weight: .bold)
        let valueView = UILabel()
        valueView.text = value
        valueView.textColor = RDColor.background
        valueView.font = .systemFont(ofSize: 22, weight: .bold)
        valueView.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [labelView, valueView])
        stack.distribution = .equalSpacing
        addSubview(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        accessibilityLabel = "%1$@, %2$@".rdLocalizedFormat(localizedLabel, value)
    }

    required init?(coder: NSCoder) { nil }
}

final class RDCameraGuideOverlay: UIView {
    private let boxLayer = CAShapeLayer()
    private var joints: [BodyJoint: JointPoint] = [:]
    private var quality: PoseQuality = .missingRequiredJoints

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        boxLayer.fillColor = UIColor.clear.cgColor
        boxLayer.lineWidth = 2
        boxLayer.lineDashPattern = [8, 6]
        layer.addSublayer(boxLayer)
    }

    required init?(coder: NSCoder) { nil }

    func update(frame: PoseFrame) {
        joints = frame.joints.filter { $0.value.confidence >= PoseQualityEvaluator.minimumJointConfidence }
        quality = frame.quality
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        boxLayer.frame = bounds
        let mapped = joints.values.map {
            PoseCoordinateTransform.aspectFill(
                $0,
                imageWidth: 720,
                imageHeight: 1280,
                viewportWidth: Double(bounds.width),
                viewportHeight: Double(bounds.height),
                mirrored: false
            )
        }
        guard let minX = mapped.map(\.x).min(),
              let maxX = mapped.map(\.x).max(),
              let minY = mapped.map(\.y).min(),
              let maxY = mapped.map(\.y).max(),
              mapped.count >= 4 else {
            boxLayer.path = nil
            boxLayer.opacity = 0
            return
        }
        let rect = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(max(1, maxX - minX)),
            height: CGFloat(max(1, maxY - minY))
        ).insetBy(dx: -14, dy: -14).intersection(bounds)
        boxLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 18).cgPath
        boxLayer.strokeColor = (quality.permitsCounting ? RDColor.neonGreen : RDColor.warning).cgColor
        boxLayer.opacity = quality.permitsCounting ? 0.92 : 0.48
    }
}

class RDBaseViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RDColor.background
        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.navigationBar.tintColor = RDColor.warmWhite
    }

    func makeScrollableContent(pinnedFooter: UIView? = nil) -> (UIScrollView, UIStackView) {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(axis: .vertical, spacing: RDSpacing.lg)
        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        var constraints = [
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -RDSpacing.lg),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: RDSpacing.lg),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -RDSpacing.lg),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * RDSpacing.lg)
        ]

        if let pinnedFooter {
            pinnedFooter.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pinnedFooter)
            constraints += [
                scrollView.bottomAnchor.constraint(equalTo: pinnedFooter.topAnchor),
                pinnedFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pinnedFooter.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                pinnedFooter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ]
        } else {
            constraints.append(scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        return (scrollView, stack)
    }

    func makeLabel(text: String, font: UIFont, color: UIColor = RDColor.warmWhite, lines: Int = 0) -> UILabel {
        let label = UILabel()
        label.text = text.rdLocalized
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}
