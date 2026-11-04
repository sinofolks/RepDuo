import UIKit

final class RDPrimaryButton: UIButton {
    enum Style {
        /// Lime parallelogram: the one forward action on a screen.
        case primary
        /// White parallelogram: forward steps that are not yet the commitment.
        case inverse
        /// Outlined rectangle for the alternative action.
        case secondary
        case destructive
    }

    private let style: Style
    private let slantMask = CAShapeLayer()

    init(title: String, style: Style = .primary, symbolName: String? = nil) {
        self.style = style
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title.rdLocalized
        configuration.image = symbolName.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(weight: .heavy))
        }
        configuration.imagePadding = 10
        configuration.imagePlacement = .trailing
        configuration.background.cornerRadius = isSlanted ? 0 : RDCornerRadius.small
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 24, bottom: 18, trailing: 24)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
                for: .systemFont(ofSize: 17, weight: .black),
                maximumPointSize: 24
            )
            return outgoing
        }
        self.configuration = configuration
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        accessibilityTraits.insert(.button)
        if isSlanted { layer.mask = slantMask }
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    private var isSlanted: Bool { style == .primary || style == .inverse }

    override var isEnabled: Bool {
        didSet { updateColors() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.82 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isSlanted { slantMask.path = UIBezierPath.rdSlanted(in: bounds).cgPath }
    }

    private func updateColors() {
        var configuration = configuration
        configuration?.background.strokeWidth = 0
        switch style {
        case .primary:
            configuration?.baseBackgroundColor = isEnabled ? RDColor.neonGreen : RDColor.surfaceSecondary
            configuration?.baseForegroundColor = isEnabled ? RDColor.background : RDColor.textMuted
        case .inverse:
            configuration?.baseBackgroundColor = isEnabled ? RDColor.warmWhite : RDColor.surfaceSecondary
            configuration?.baseForegroundColor = isEnabled ? RDColor.background : RDColor.textMuted
        case .secondary:
            configuration?.baseBackgroundColor = .clear
            configuration?.baseForegroundColor = isEnabled ? RDColor.warmWhite : RDColor.textMuted
            configuration?.background.strokeColor = RDColor.separatorStrong
            configuration?.background.strokeWidth = 1.5
        case .destructive:
            configuration?.baseBackgroundColor = RDColor.destructive.withAlphaComponent(isEnabled ? 0.16 : 0.08)
            configuration?.baseForegroundColor = isEnabled ? RDColor.destructive : RDColor.textMuted
        }
        self.configuration = configuration
    }
}

/// Label for large slanted numerals. The sheared glyphs lean past their advance
/// width, so the label reserves trailing room instead of letting them clip.
final class RDNumberLabel: UILabel {
    private var slantInset: CGFloat { ceil(font.pointSize * 0.22) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + slantInset, height: size.height)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: slantInset)))
    }
}

/// Round icon-only control used in headers and the workout control bar.
final class RDIconButton: UIButton {
    init(symbolName: String, accessibilityLabel: String, diameter: CGFloat = 44, background: UIColor = RDColor.surfaceRaised) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter > 50 ? 20 : 16, weight: .bold)
        )
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = RDColor.warmWhite
        self.configuration = configuration
        self.accessibilityLabel = accessibilityLabel.rdLocalized
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setSymbol(_ symbolName: String) {
        configuration?.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: bounds.width > 50 ? 20 : 16, weight: .bold)
        )
    }
}

/// Slanted label chip: streaks, phases, records.
final class RDTag: UIView {
    private let label = UILabel()
    private let iconView = UIImageView()
    private let slantMask = CAShapeLayer()

    init(text: String = "", symbolName: String? = nil, background: UIColor, foreground: UIColor = RDColor.background) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = background
        layer.mask = slantMask
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 14, weight: .black),
            maximumPointSize: 20
        )
        label.adjustsFontForContentSizeCategory = true
        label.textColor = foreground
        label.text = text.rdLocalized
        iconView.image = symbolName.flatMap {
            UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy))
        }
        iconView.tintColor = foreground
        iconView.isHidden = symbolName == nil
        let stack = UIStackView(axis: .horizontal, spacing: 5, arrangedSubviews: [iconView, label])
        stack.alignment = .center
        addSubview(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    var text: String? {
        get { label.text }
        set {
            label.text = newValue
            accessibilityLabel = newValue
        }
    }

    func setColors(background: UIColor, foreground: UIColor) {
        backgroundColor = background
        label.textColor = foreground
        iconView.tintColor = foreground
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        slantMask.path = UIBezierPath.rdSlanted(in: bounds, slant: 7).cgPath
    }
}

private final class RDLogoMarkView: UIView {
    private let leadingColor: UIColor
    private let trailingColor: UIColor

    init(leadingColor: UIColor, trailingColor: UIColor) {
        self.leadingColor = leadingColor
        self.trailingColor = trailingColor
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
        context.setStrokeColor(trailingColor.cgColor)
        context.strokePath()
    }
}

final class RDWordmarkView: UIView {
    enum Surface {
        case dark
        /// Black mark on a lime surface, such as the share card.
        case neon
    }

    init(surface: Surface = .dark, size: CGFloat = 24) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = "RepDuo"
        let ink = surface == .dark ? RDColor.warmWhite : RDColor.background
        let mark = RDLogoMarkView(leadingColor: ink, trailingColor: surface == .dark ? RDColor.neonGreen : RDColor.background)
        let wordmark = UILabel()
        wordmark.text = "REPDUO"
        wordmark.textColor = ink
        wordmark.font = RDFont.numeric(size, maximumScale: 1)
        let content = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [mark, wordmark])
        content.alignment = .center
        content.isUserInteractionEnabled = false
        addSubview(content)
        content.pinEdges(to: self)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: size * 1.42),
            mark.heightAnchor.constraint(equalToConstant: size * 0.75)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// Capsule status with a leading dot, tinted by tone.
final class RDStatusPill: UIView {
    private let dot = UIView()
    private let label = UILabel()

    init(text: String, positive: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13, weight: .bold),
            maximumPointSize: 18
        )
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        update(text: text.rdLocalized, tone: positive ? RDColor.neonGreen : RDColor.warning)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func update(text: String, tone: UIColor) {
        label.text = text
        label.textColor = tone
        dot.backgroundColor = tone
        backgroundColor = tone.withAlphaComponent(0.13)
    }
}

/// Big condensed number over a small caption, on a dark tile.
final class RDStatTile: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    init(value: String = "—", caption: String, valueColor: UIColor = RDColor.warmWhite, valueSize: CGFloat = 28, filled: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = filled ? RDColor.surface : .clear
        layer.cornerRadius = RDCornerRadius.small
        valueLabel.font = RDFont.numeric(valueSize)
        valueLabel.textColor = valueColor
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.adjustsFontForContentSizeCategory = true
        captionLabel.font = RDFont.caption(weight: .medium)
        captionLabel.textColor = RDColor.textSecondary
        captionLabel.numberOfLines = 2
        captionLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [valueLabel, captionLabel])
        addSubview(stack)
        stack.pinEdges(to: self, insets: filled
            ? NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            : .zero)
        isAccessibilityElement = true
        update(value: value, caption: caption.rdLocalized)
    }

    required init?(coder: NSCoder) { nil }

    func update(value: String, caption: String? = nil, valueColor: UIColor? = nil) {
        valueLabel.text = value
        if let caption { captionLabel.text = caption }
        if let valueColor { valueLabel.textColor = valueColor }
        accessibilityLabel = "%1$@, %2$@".rdLocalizedFormat(captionLabel.text ?? "", value)
    }
}

/// Circular progress ring with an optional centered content view.
final class RDRingView: UIView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    var lineWidth: CGFloat = 14 { didSet { setNeedsLayout() } }
    var progressColor: UIColor = RDColor.neonGreen { didSet { progressLayer.strokeColor = progressColor.cgColor } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        for shape in [trackLayer, progressLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        trackLayer.strokeColor = RDColor.surfaceSecondary.cgColor
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.strokeEnd = 0
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: max(0, radius),
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        ).cgPath
        for shape in [trackLayer, progressLayer] {
            shape.frame = bounds
            shape.path = path
            shape.lineWidth = lineWidth
        }
    }

    func setProgress(_ value: CGFloat, animated: Bool) {
        let clamped = max(0, min(1, value))
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || UIAccessibility.isReduceMotionEnabled)
        CATransaction.setAnimationDuration(0.6)
        progressLayer.strokeEnd = clamped
        CATransaction.commit()
    }
}

/// Small weekly bar chart with day labels; the highlighted bar is today.
final class RDBarChartView: UIView {
    private let barsStack = UIStackView(axis: .horizontal, spacing: 4)
    private let barHeight: CGFloat

    init(barHeight: CGFloat = 38) {
        self.barHeight = barHeight
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        barsStack.distribution = .fillEqually
        barsStack.alignment = .bottom
        addSubview(barsStack)
        barsStack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { nil }

    func render(values: [Int], labels: [String], highlightIndex: Int, highlightColor: UIColor = RDColor.neonGreen) {
        barsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let peak = max(values.max() ?? 0, 1)
        for (index, value) in values.enumerated() {
            let isToday = index == highlightIndex
            let bar = RDSlantedBlockView(slant: 3)
            bar.fillColor = isToday ? highlightColor : (value == 0 ? RDColor.surfaceSecondary : RDColor.separatorStrong)
            let height = value == 0 ? 3 : max(6, barHeight * CGFloat(value) / CGFloat(peak))
            bar.heightAnchor.constraint(equalToConstant: height).isActive = true
            let label = UILabel()
            label.text = labels.indices.contains(index) ? labels[index] : ""
            label.font = .systemFont(ofSize: 11, weight: .bold)
            label.textColor = isToday ? highlightColor : RDColor.textMuted
            label.textAlignment = .center
            let column = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [bar, label])
            column.alignment = .fill
            barsStack.addArrangedSubview(column)
        }
        isAccessibilityElement = true
        accessibilityLabel = zip(labels, values).map { "\($0) \($1)" }.joined(separator: ", ")
    }
}

/// Solid parallelogram block for bars and progress segments.
final class RDSlantedBlockView: UIView {
    private let slant: CGFloat
    var fillColor: UIColor = RDColor.surfaceSecondary { didSet { setNeedsDisplay() } }

    init(slant: CGFloat) {
        self.slant = slant
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        fillColor.setFill()
        UIBezierPath.rdSlanted(in: bounds, slant: slant).fill()
    }
}

/// Row of skewed segments that fill up toward a set target.
final class RDSegmentBar: UIView {
    private var segments: [RDSlantedBlockView] = []
    private let stack = UIStackView(axis: .horizontal, spacing: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fillEqually
        addSubview(stack)
        stack.pinEdges(to: self)
        heightAnchor.constraint(equalToConstant: 10).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    func render(filled: Int, total: Int, color: UIColor) {
        let total = max(1, total)
        if segments.count != total {
            segments.forEach { $0.removeFromSuperview() }
            segments = (0..<total).map { _ in RDSlantedBlockView(slant: 2.5) }
            segments.forEach(stack.addArrangedSubview)
            stack.spacing = total > 30 ? 1 : 2
        }
        for (index, segment) in segments.enumerated() {
            segment.fillColor = index < filled ? color : RDColor.separatorOnDark
        }
    }
}

/// Four-week training calendar, one cell per day, oldest first.
final class RDHeatmapView: UIView {
    private let grid = UIStackView(axis: .vertical, spacing: 5)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        grid.distribution = .fillEqually
        addSubview(grid)
        grid.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { nil }

    static let shades = [RDColor.surfaceSecondary, UIColor(hex: 0x4F6B0C), UIColor(hex: 0x8DB515), RDColor.neonGreen]

    func render(dailyReps: [Int]) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let peak = max(dailyReps.max() ?? 0, 1)
        stride(from: 0, to: dailyReps.count, by: 7).forEach { start in
            let row = UIStackView(axis: .horizontal, spacing: 5)
            row.distribution = .fillEqually
            for index in start..<min(start + 7, dailyReps.count) {
                let value = dailyReps[index]
                let level = value == 0 ? 0 : min(3, 1 + Int(Double(value) / Double(peak) * 2.99))
                let cell = UIView()
                cell.backgroundColor = Self.shades[level]
                cell.layer.cornerRadius = 2
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.heightAnchor.constraint(equalTo: cell.widthAnchor, multiplier: 0.55).isActive = true
                if index == dailyReps.count - 1 {
                    cell.layer.borderColor = RDColor.warmWhite.cgColor
                    cell.layer.borderWidth = 2
                }
                row.addArrangedSubview(cell)
            }
            grid.addArrangedSubview(row)
        }
        isAccessibilityElement = true
        accessibilityLabel = "Training days in the last four weeks: %d".rdLocalizedFormat(dailyReps.filter { $0 > 0 }.count)
    }
}

final class RDDeviceStatusCard: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let statusDot = UIView()
    private let detailLabel = UILabel()

    init(symbol: String, title: String, iconTint: UIColor = RDColor.warmWhite) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.surface
        layer.cornerRadius = RDCornerRadius.small

        let iconBox = UIView()
        iconBox.backgroundColor = RDColor.surfaceSecondary
        iconBox.layer.cornerRadius = 26
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = iconTint
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)

        titleLabel.text = title.rdLocalized
        titleLabel.textColor = RDColor.warmWhite
        titleLabel.font = RDFont.body(weight: .black)
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = RDColor.textSecondary
        detailLabel.font = RDFont.caption(weight: .regular)
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        statusLabel.font = .systemFont(ofSize: 13, weight: .bold)
        statusDot.layer.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        let status = UIStackView(axis: .horizontal, spacing: 6, arrangedSubviews: [statusDot, statusLabel])
        status.alignment = .center
        status.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.required, for: .horizontal)

        let labels = UIStackView(axis: .vertical, spacing: 3, arrangedSubviews: [titleLabel, detailLabel])
        let row = UIStackView(axis: .horizontal, spacing: 14, arrangedSubviews: [iconBox, labels, status])
        row.alignment = .center
        addSubview(row)
        row.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 52),
            iconBox.heightAnchor.constraint(equalToConstant: 52),
            iconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8)
        ])
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    func update(status: String, detail: String, connected: Bool) {
        let localizedStatus = status.rdLocalized
        let localizedDetail = detail.rdLocalized
        let tone = connected ? RDColor.neonGreen : RDColor.textMuted
        statusLabel.text = localizedStatus
        statusLabel.textColor = tone
        statusDot.backgroundColor = tone
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
    private let tagLabel = UILabel()
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let bestLabel = UILabel()

    let exercise: ExerciseType

    init(exercise: ExerciseType) {
        self.exercise = exercise
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = RDCornerRadius.small
        layer.borderWidth = 2

        symbolView.image = UIImage(systemName: exercise.symbolName)
        symbolView.contentMode = .scaleAspectFit
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        tagLabel.setEyebrow(exercise.scoreboardName)
        dot.layer.cornerRadius = 7
        dot.layer.borderWidth = 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = exercise.displayName
        titleLabel.font = RDFont.title(24)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        bestLabel.font = RDFont.caption(weight: .medium)
        bestLabel.adjustsFontForContentSizeCategory = true

        let top = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [tagLabel, UIView(), dot])
        top.alignment = .center
        let names = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [titleLabel, bestLabel])
        let bottom = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [names, symbolView])
        bottom.alignment = .bottom
        let stack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [top, bottom])
        stack.distribution = .equalSpacing
        // Keep the whole visible card as one hit target. Otherwise the layout
        // stack can win hit-testing and prevent this UIControl from receiving
        // touchUpInside when users tap its labels or symbol.
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 132),
            dot.widthAnchor.constraint(equalToConstant: 14),
            dot.heightAnchor.constraint(equalToConstant: 14),
            symbolView.widthAnchor.constraint(equalToConstant: 40),
            symbolView.heightAnchor.constraint(equalToConstant: 40)
        ])
        accessibilityTraits = .button
        setPersonalBest(0)
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : 1 }
    }

    func setPersonalBest(_ reps: Int) {
        bestLabel.text = reps > 0 ? "Best %d reps".rdLocalizedFormat(reps) : "No sets yet".rdLocalized
        accessibilityLabel = "%1$@, %2$@".rdLocalizedFormat(exercise.displayName, bestLabel.text ?? "")
    }

    private func updateAppearance() {
        let accent = isSelected ? RDColor.neonGreen : RDColor.warmWhite
        backgroundColor = isSelected ? RDColor.neonTint : RDColor.surface
        layer.borderColor = (isSelected ? RDColor.neonGreen : RDColor.surfaceSecondary).cgColor
        titleLabel.textColor = accent
        symbolView.tintColor = accent
        tagLabel.textColor = isSelected ? RDColor.neonGreen : RDColor.textMuted
        bestLabel.textColor = isSelected ? RDColor.warmWhite : RDColor.textSecondary
        dot.layer.borderColor = (isSelected ? RDColor.neonGreen : RDColor.separatorStrong).cgColor
        dot.backgroundColor = isSelected ? RDColor.neonGreen : .clear
        accessibilityValue = (isSelected ? "Selected" : "Not selected").rdLocalized
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

/// Lime corner brackets around the tracked body; amber while the pose is not usable.
final class RDCameraGuideOverlay: UIView {
    private let cornersLayer = CAShapeLayer()
    private var joints: [BodyJoint: JointPoint] = [:]
    private var quality: PoseQuality = .missingRequiredJoints

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        cornersLayer.fillColor = UIColor.clear.cgColor
        cornersLayer.lineWidth = 4
        cornersLayer.lineCap = .square
        layer.addSublayer(cornersLayer)
    }

    required init?(coder: NSCoder) { nil }

    func update(frame: PoseFrame) {
        joints = frame.joints.filter { $0.value.confidence >= PoseQualityEvaluator.minimumJointConfidence }
        quality = frame.quality
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cornersLayer.frame = bounds
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
            cornersLayer.path = nil
            cornersLayer.opacity = 0
            return
        }
        let rect = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(max(1, maxX - minX)),
            height: CGFloat(max(1, maxY - minY))
        ).insetBy(dx: -18, dy: -18).intersection(bounds.insetBy(dx: 2, dy: 2))
        let arm = min(34, rect.width / 3, rect.height / 3)
        let path = UIBezierPath()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), arm, arm),
            (CGPoint(x: rect.maxX, y: rect.minY), -arm, arm),
            (CGPoint(x: rect.minX, y: rect.maxY), arm, -arm),
            (CGPoint(x: rect.maxX, y: rect.maxY), -arm, -arm)
        ] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx, y: corner.y))
        }
        cornersLayer.path = path.cgPath
        cornersLayer.strokeColor = (quality.permitsCounting ? RDColor.neonGreen : RDColor.warning).cgColor
        cornersLayer.opacity = quality.permitsCounting ? 1 : 0.6
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
        let margin = RDLayout.screenMargin

        var constraints = [
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -margin),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: RDSpacing.md),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -RDSpacing.lg),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * margin)
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

    /// Footer bar for pinned actions, with screen margins applied.
    func makeFooter(_ views: [UIView], axis: NSLayoutConstraint.Axis = .horizontal) -> UIStackView {
        let footer = UIStackView(axis: axis, spacing: 10, arrangedSubviews: views)
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: RDSpacing.sm,
            leading: RDLayout.screenMargin,
            bottom: RDSpacing.md,
            trailing: RDLayout.screenMargin
        )
        footer.backgroundColor = view.backgroundColor
        return footer
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

    func makeEyebrow(_ text: String, color: UIColor = RDColor.textSecondary) -> UILabel {
        let label = UILabel()
        label.setEyebrow(text.rdLocalized, color: color)
        label.numberOfLines = 0
        return label
    }

    func makeCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = RDColor.surface
        card.layer.cornerRadius = RDCornerRadius.small
        return card
    }
}
