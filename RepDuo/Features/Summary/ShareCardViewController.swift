import UIKit

struct ShareCardContent {
    let summary: WorkoutSummary
    let isNewRecord: Bool
    let streakDays: Int
}

/// Poster-style result card the user can save or share. Rendered on-device;
/// only the image the user chooses to share leaves the app.
final class ShareCardViewController: RDBaseViewController {
    private let content: ShareCardContent
    private let card: ShareCardView
    private var themeButtons: [UIButton] = []

    init(content: ShareCardContent) {
        self.content = content
        self.card = ShareCardView(content: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RDColor.backgroundDeep

        let close = RDIconButton(symbolName: "xmark", accessibilityLabel: "Close")
        close.accessibilityIdentifier = "share.close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        let title = makeLabel(text: "Share result", font: RDFont.body(weight: .black))
        title.textAlignment = .center
        let spacer = UIView()
        spacer.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let header = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [close, title, spacer])
        header.alignment = .center

        let themes = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: ShareCardView.Theme.allCases.map(makeThemeButton))
        let themesRow = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [UIView(), themes, UIView()])
        themesRow.distribution = .equalCentering

        let save = RDPrimaryButton(title: "Save to Photos", style: .secondary)
        save.accessibilityIdentifier = "share.save"
        save.addAction(UIAction { [weak self] _ in self?.saveToPhotos() }, for: .touchUpInside)
        let share = RDPrimaryButton(title: "Share", symbolName: "square.and.arrow.up")
        share.accessibilityIdentifier = "share.share"
        share.addAction(UIAction { [weak self] action in self?.presentShareSheet(from: action.sender as? UIView) }, for: .touchUpInside)
        let actions = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [save, share])
        actions.distribution = .fillEqually

        [header, card, themesRow, actions].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: RDLayout.screenMargin),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -RDLayout.screenMargin),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            card.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            card.widthAnchor.constraint(equalTo: card.heightAnchor, multiplier: ShareCardView.aspectRatio),
            card.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -2 * RDLayout.screenMargin),
            card.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -2 * RDLayout.screenMargin).withPriority(.defaultHigh),
            themesRow.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 14),
            themesRow.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            themesRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            actions.topAnchor.constraint(greaterThanOrEqualTo: themesRow.bottomAnchor, constant: 16),
            actions.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: RDLayout.screenMargin),
            actions.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -RDLayout.screenMargin),
            actions.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -RDSpacing.md)
        ])
        select(.neon)
    }

    private func makeThemeButton(_ theme: ShareCardView.Theme) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = theme.title.rdLocalized
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        button.configuration = configuration
        button.tag = ShareCardView.Theme.allCases.firstIndex(of: theme) ?? 0
        button.addAction(UIAction { [weak self] _ in self?.select(theme) }, for: .touchUpInside)
        themeButtons.append(button)
        return button
    }

    private func select(_ theme: ShareCardView.Theme) {
        card.theme = theme
        for button in themeButtons {
            let isSelected = ShareCardView.Theme.allCases[button.tag] == theme
            button.configuration?.baseBackgroundColor = isSelected ? RDColor.warmWhite : RDColor.surfaceSecondary
            button.configuration?.baseForegroundColor = isSelected ? RDColor.background : RDColor.textBody
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    private func renderImage() -> UIImage {
        card.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        // Export at 1080 px wide regardless of the on-screen size.
        format.scale = 1080 / max(card.bounds.width, 1)
        return UIGraphicsImageRenderer(bounds: card.bounds, format: format).image { context in
            card.layer.render(in: context.cgContext)
        }
    }

    private func presentShareSheet(from source: UIView?) {
        let controller = UIActivityViewController(activityItems: [renderImage()], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = source ?? view
        present(controller, animated: true)
    }

    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(renderImage(), self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let message = error == nil ? "Saved to Photos".rdLocalized : error?.localizedDescription
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK".rdLocalized, style: .default))
        present(alert, animated: true)
    }
}

final class ShareCardView: UIView {
    enum Theme: CaseIterable {
        case neon
        case night
        case blaze

        var title: String {
            switch self {
            case .neon: return "Neon"
            case .night: return "Night"
            case .blaze: return "Blaze"
            }
        }

        var background: UIColor {
            switch self {
            case .neon: return RDColor.neonGreen
            case .night: return RDColor.surface
            case .blaze: return RDColor.ember
            }
        }

        var ink: UIColor { self == .night ? RDColor.warmWhite : RDColor.background }
        var accent: UIColor { self == .night ? RDColor.neonGreen : RDColor.background }
    }

    static let aspectRatio: CGFloat = 0.6

    private let content: ShareCardContent
    private let cutMask = CAShapeLayer()
    private let watermark = UILabel()
    private let headlineTag = RDTag(background: RDColor.background, foreground: RDColor.ember)
    private var inkLabels: [UILabel] = []
    private var accentLabels: [UILabel] = []
    private let divider = UIView()
    private var wordmarkHost = UIView()

    var theme: Theme = .neon { didSet { applyTheme() } }

    init(content: ShareCardContent) {
        self.content = content
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.mask = cutMask
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "%1$@, %2$d reps".rdLocalizedFormat(content.summary.exercise.displayName, content.summary.repCount)
        build()
        applyTheme()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cut: CGFloat = 24
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: bounds.maxX, y: 0))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cut))
        path.addLine(to: CGPoint(x: bounds.maxX - cut, y: bounds.maxY))
        path.addLine(to: CGPoint(x: 0, y: bounds.maxY))
        path.close()
        cutMask.path = path.cgPath
        // Type scales with the card so the exported poster matches the preview.
        let scale = bounds.width / 330
        countLabel.font = RDFont.numeric(190 * scale, maximumScale: 1)
        watermark.font = RDFont.numeric(250 * scale, maximumScale: 1)
    }

    private let countLabel = RDNumberLabel()

    private func build() {
        let summary = content.summary
        watermark.text = content.isNewRecord ? "PB" : "REP"
        watermark.translatesAutoresizingMaskIntoConstraints = false
        watermark.isAccessibilityElement = false
        addSubview(watermark)

        let date = label(summary.startedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)), font: RDFont.numeric(14, weight: .heavy, italic: false))
        let top = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [wordmarkHost, UIView(), date])
        top.alignment = .center

        headlineTag.text = content.isNewRecord
            ? "%1$@ · %2$@".rdLocalizedFormat("NEW RECORD".rdLocalized, summary.exercise.displayName)
            : summary.exercise.displayName
        let tagRow = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [headlineTag, UIView()])

        countLabel.text = String(summary.repCount)
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.4
        inkLabels.append(countLabel)
        let unit = label("REPS_UNIT".rdLocalized, font: RDFont.title(24))
        let countRow = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [countLabel, unit, UIView()])
        countRow.alignment = .lastBaseline
        let tagline = label(
            (content.isNewRecord ? "New record. You're on fire." : "One strong set. Keep the rhythm.").rdLocalized,
            font: RDFont.title(20)
        )
        tagline.numberOfLines = 2

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 2).isActive = true
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        let stats = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [
            stat(summary.coachingReport?.averageScore.map { String($0) } ?? "—", "AI form score"),
            stat(formatter.string(from: summary.activeDuration) ?? "0:00", "Duration"),
            stat("%d d".rdLocalizedFormat(content.streakDays), "Streak")
        ])
        stats.distribution = .fillEqually

        let stack = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [top, UIView(), tagRow, countRow, tagline, divider, stats])
        stack.setCustomSpacing(4, after: tagRow)
        stack.setCustomSpacing(18, after: tagline)
        stack.setCustomSpacing(12, after: divider)
        addSubview(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 30, trailing: 24))
        NSLayoutConstraint.activate([
            watermark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 24),
            watermark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40)
        ])
    }

    private func stat(_ value: String, _ caption: String) -> UIView {
        let valueLabel = label(value, font: RDFont.numeric(30, maximumScale: 1))
        let captionLabel = label(caption.rdLocalized, font: .systemFont(ofSize: 12, weight: .bold))
        return UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [valueLabel, captionLabel])
    }

    private func label(_ text: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        inkLabels.append(label)
        return label
    }

    private func applyTheme() {
        backgroundColor = theme.background
        inkLabels.forEach { $0.textColor = theme.ink }
        countLabel.textColor = theme.accent == RDColor.neonGreen ? RDColor.neonGreen : theme.ink
        divider.backgroundColor = theme.ink
        watermark.textColor = .clear
        watermark.attributedText = NSAttributedString(string: watermark.text ?? "", attributes: [
            .strokeColor: theme.ink.withAlphaComponent(0.16),
            .strokeWidth: 3,
            .font: watermark.font as Any
        ])
        headlineTag.setColors(
            background: theme == .night ? RDColor.neonGreen : RDColor.background,
            foreground: theme == .night ? RDColor.background : (theme == .blaze ? RDColor.warmWhite : RDColor.ember)
        )
        wordmarkHost.subviews.forEach { $0.removeFromSuperview() }
        let wordmark = RDWordmarkView(surface: theme == .night ? .dark : .neon, size: 20)
        wordmarkHost.addSubview(wordmark)
        wordmark.pinEdges(to: wordmarkHost)
    }
}
