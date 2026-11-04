import UIKit

final class OnboardingViewController: RDBaseViewController {
    private struct Page {
        let eyebrow: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(
            eyebrow: "01 · AUTO COUNT",
            title: "PROP IT UP.\nWE COUNT.",
            body: "The front camera reads your pose live and counts every squat and push-up. No wearables, no mental math."
        ),
        Page(
            eyebrow: "02 · AI FORM SCORE",
            title: "EVERY REP\nGETS A SCORE.",
            body: "Range, tempo, and symmetry are scored. The first three reps learn your baseline, then cues get personal."
        ),
        Page(
            eyebrow: "03 · PRIVATE BY DESIGN",
            title: "YOUR CAMERA.\nYOUR DATA.",
            body: "Frames are processed on this iPhone only. Video is never saved or uploaded; history keeps reps and time."
        )
    ]

    private var pageIndex = 0
    private let visualContainer = UIView()
    private var visuals: [UIView] = []
    private let dotsStack = UIStackView(axis: .horizontal, spacing: 6)
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let skipButton = UIButton(type: .system)
    private let nextButton = RDPrimaryButton(title: "NEXT", style: .inverse)
    private let getStartedButton = RDPrimaryButton(title: "ALLOW CAMERA & TRAIN")

    var onContinue: (() -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true

        nextButton.accessibilityIdentifier = "onboarding.next"
        nextButton.addAction(UIAction { [weak self] _ in self?.show(page: (self?.pageIndex ?? 0) + 1) }, for: .touchUpInside)
        getStartedButton.accessibilityIdentifier = "onboarding.getStarted"
        getStartedButton.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)
        let footer = makeFooter([nextButton, getStartedButton], axis: .vertical)
        let (_, stack) = makeScrollableContent(pinnedFooter: footer)
        stack.spacing = RDSpacing.md

        skipButton.setTitle("SKIP".rdLocalized, for: .normal)
        skipButton.setTitleColor(RDColor.accent, for: .normal)
        skipButton.titleLabel?.font = RDFont.body(weight: .regular)
        skipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skipButton.accessibilityIdentifier = "onboarding.skip"
        skipButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        skipButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.show(page: self.pages.count - 1)
        }, for: .touchUpInside)
        let header = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [RDWordmarkView(), UIView(), skipButton])
        header.alignment = .center

        visualContainer.translatesAutoresizingMaskIntoConstraints = false
        visualContainer.heightAnchor.constraint(equalToConstant: 320).isActive = true
        visuals = [makeCountVisual(), makeScoreVisual(), makePrivacyVisual()]
        for visual in visuals {
            visualContainer.addSubview(visual)
            NSLayoutConstraint.activate([
                visual.centerXAnchor.constraint(equalTo: visualContainer.centerXAnchor),
                visual.centerYAnchor.constraint(equalTo: visualContainer.centerYAnchor),
                visual.widthAnchor.constraint(equalTo: visualContainer.widthAnchor, multiplier: 0.86),
                visual.heightAnchor.constraint(lessThanOrEqualTo: visualContainer.heightAnchor)
            ])
        }

        dotsStack.alignment = .center
        eyebrowLabel.numberOfLines = 0
        titleLabel.font = RDFont.title(34)
        titleLabel.textColor = RDColor.label
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        bodyLabel.font = RDFont.body()
        bodyLabel.textColor = RDColor.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true

        let dotsRow = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [dotsStack, UIView()])
        [header, visualContainer, dotsRow, eyebrowLabel, titleLabel, bodyLabel].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(RDSpacing.lg, after: dotsRow)
        stack.setCustomSpacing(6, after: eyebrowLabel)

        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
        show(page: 0, animated: false)
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        show(page: pageIndex + (gesture.direction == .left ? 1 : -1))
    }

    private func show(page: Int, animated: Bool = true) {
        let target = max(0, min(pages.count - 1, page))
        guard target != pageIndex || !animated else { return }
        pageIndex = target
        let content = pages[target]
        let isLast = target == pages.count - 1
        let apply = {
            self.eyebrowLabel.setEyebrow(content.eyebrow.rdLocalized)
            self.titleLabel.text = content.title.rdLocalized
            self.bodyLabel.text = content.body.rdLocalized
            for (index, visual) in self.visuals.enumerated() { visual.alpha = index == target ? 1 : 0 }
            self.nextButton.isHidden = isLast
            self.getStartedButton.isHidden = !isLast
            self.skipButton.alpha = isLast ? 0 : 1
            self.skipButton.isEnabled = !isLast
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.25, animations: apply)
        } else {
            apply()
        }
        renderDots()
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    private func renderDots() {
        dotsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for index in pages.indices {
            let dot = UIView()
            dot.backgroundColor = index == pageIndex ? RDColor.accent : RDColor.separator
            dot.layer.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.heightAnchor.constraint(equalToConstant: 6),
                dot.widthAnchor.constraint(equalToConstant: index == pageIndex ? 28 : 6)
            ])
            dotsStack.addArrangedSubview(dot)
        }
        dotsStack.isAccessibilityElement = true
        dotsStack.accessibilityLabel = "Page %1$d of %2$d".rdLocalizedFormat(pageIndex + 1, pages.count)
    }

    // MARK: Page visuals

    private func makeCountVisual() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isAccessibilityElement = false
        let figure = RDNeonFigureView()
        let count = RDNumberLabel()
        count.text = "12"
        count.font = RDFont.numeric(120, maximumScale: 1)
        count.textColor = RDColor.label
        count.translatesAutoresizingMaskIntoConstraints = false
        let tag = RDTag(text: "+1 AUTO COUNT")
        [figure, count, tag].forEach(container.addSubview)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 320),
            figure.centerXAnchor.constraint(equalTo: container.centerXAnchor, constant: -20),
            figure.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            figure.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            figure.widthAnchor.constraint(equalTo: figure.heightAnchor, multiplier: 0.5),
            count.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            count.topAnchor.constraint(equalTo: container.topAnchor),
            tag.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tag.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -30)
        ])
        return container
    }

    private func makeScoreVisual() -> UIView {
        let ring = RDRingView()
        ring.lineWidth = 14
        ring.setProgress(0.86, animated: false)
        let score = RDNumberLabel()
        score.text = "86"
        score.font = RDFont.numeric(84, maximumScale: 1)
        score.textColor = RDColor.label
        let caption = UILabel()
        caption.setEyebrow("AI SCORE")
        let center = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [score, caption])
        center.alignment = .center
        ring.addSubview(center)
        center.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 200),
            ring.heightAnchor.constraint(equalToConstant: 200),
            center.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            center.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])
        let metrics = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [
            metricTile("RANGE", value: 0.92, tone: RDColor.accent),
            metricTile("TEMPO", value: 0.78, tone: RDColor.accent),
            metricTile("SYMMETRY", value: 0.86, tone: RDColor.accent)
        ])
        metrics.distribution = .fillEqually
        let stack = UIStackView(axis: .vertical, spacing: 24, arrangedSubviews: [ring, metrics])
        stack.alignment = .center
        metrics.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.isAccessibilityElement = false
        return stack
    }

    private func metricTile(_ title: String, value: CGFloat, tone: UIColor) -> UIView {
        let tile = makeCard()
        let label = makeLabel(text: title, font: RDFont.caption(weight: .medium), color: RDColor.label)
        let track = UIView()
        track.backgroundColor = RDColor.fill
        track.layer.cornerRadius = 2
        let fill = UIView()
        fill.backgroundColor = tone
        fill.layer.cornerRadius = 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        let stack = UIStackView(axis: .vertical, spacing: 6, arrangedSubviews: [label, track])
        tile.addSubview(stack)
        stack.pinEdges(to: tile, insets: NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        NSLayoutConstraint.activate([
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: value)
        ])
        return tile
    }

    private func makePrivacyVisual() -> UIView {
        let shield = UIImageView(image: UIImage(
            systemName: "lock.shield",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 120, weight: .thin)
        ))
        shield.tintColor = RDColor.accent
        shield.contentMode = .scaleAspectFit
        let facts = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [
            RDStatTile(value: "0", caption: "Video saved"),
            RDStatTile(value: "0", caption: "Uploads"),
            RDStatTile(value: "100%", caption: "On-device", valueColor: RDColor.accent)
        ])
        facts.distribution = .fillEqually
        let stack = UIStackView(axis: .vertical, spacing: 28, arrangedSubviews: [shield, facts])
        stack.alignment = .center
        facts.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}

/// Stylized skeleton in a squat, drawn for onboarding where no camera runs yet.
final class RDNeonFigureView: UIView {
    private let bones = CAShapeLayer()
    private let joints = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        bones.fillColor = UIColor.clear.cgColor
        bones.lineWidth = 5
        bones.lineCap = .round
        bones.lineJoin = .round
        joints.lineWidth = 3
        layer.addSublayer(bones)
        layer.addSublayer(joints)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in view.updateColors() }
    }

    private func updateColors() {
        bones.strokeColor = RDColor.accent.resolvedColor(with: traitCollection).cgColor
        joints.fillColor = RDColor.background.resolvedColor(with: traitCollection).cgColor
        joints.strokeColor = RDColor.label.resolvedColor(with: traitCollection).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Points are authored on a 200 × 400 canvas.
        let scale = min(bounds.width / 200, bounds.height / 400)
        let origin = CGPoint(x: (bounds.width - 200 * scale) / 2, y: (bounds.height - 400 * scale) / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }

        let body = UIBezierPath(ovalIn: CGRect(x: origin.x + 80 * scale, y: origin.y + 72 * scale, width: 40 * scale, height: 40 * scale))
        let segments: [[CGPoint]] = [
            [p(100, 114), p(100, 246)],
            [p(66, 136), p(134, 136)],
            [p(66, 136), p(58, 176), p(80, 186)],
            [p(134, 136), p(142, 176), p(120, 186)],
            [p(76, 250), p(124, 250)],
            [p(76, 250), p(46, 300), p(66, 372)],
            [p(124, 250), p(154, 300), p(134, 372)]
        ]
        for segment in segments {
            body.move(to: segment[0])
            segment.dropFirst().forEach { body.addLine(to: $0) }
        }
        bones.frame = bounds
        bones.lineWidth = max(3, 5 * scale)
        bones.path = body.cgPath

        let dots = UIBezierPath()
        for point in [p(66, 136), p(134, 136), p(76, 250), p(124, 250), p(46, 300), p(154, 300), p(66, 372), p(134, 372)] {
            dots.append(UIBezierPath(arcCenter: point, radius: 6 * scale, startAngle: 0, endAngle: .pi * 2, clockwise: true))
        }
        joints.frame = bounds
        joints.path = dots.cgPath
    }
}
