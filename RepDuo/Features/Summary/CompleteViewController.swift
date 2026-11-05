import UIKit

final class CompleteViewController: UIViewController {
    private let summary: WorkoutSummary
    private let stats: WorkoutStats
    private let previousBest: Int
    private let headerStack = UIStackView(axis: .vertical, spacing: 6)
    private var headerTop: NSLayoutConstraint?
    var onDone: (() -> Void)?
    var onAnotherSet: (() -> Void)?
    var onShare: ((ShareCardContent) -> Void)?

    /// `stats` already include `summary`; `previousBest` is this exercise's best before the set.
    init(summary: WorkoutSummary, stats: WorkoutStats, previousBest: Int) {
        self.summary = summary
        self.stats = stats
        self.previousBest = previousBest
        super.init(nibName: nil, bundle: nil)
    }

    private var isNewRecord: Bool { previousBest > 0 && summary.repCount > previousBest }

    required init?(coder: NSCoder) { nil }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        headerTop?.constant = view.safeAreaInsets.top + 12
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RDColor.background
        navigationItem.hidesBackButton = true

        let share = RDIconButton(symbolName: "square.and.arrow.up", accessibilityLabel: "Share result", diameter: 64, background: RDColor.surface)
        share.accessibilityIdentifier = "summary.share"
        share.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onShare?(ShareCardContent(
                summary: self.summary,
                isNewRecord: self.isNewRecord,
                streakDays: self.stats.streakDays
            ))
        }, for: .touchUpInside)
        let another = RDPrimaryButton(title: "DO ANOTHER SET", style: .secondary)
        another.accessibilityIdentifier = "summary.another"
        another.addAction(UIAction { [weak self] _ in self?.onAnotherSet?() }, for: .touchUpInside)
        let done = RDPrimaryButton(title: "DONE")
        done.accessibilityIdentifier = "summary.done"
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        let footer = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [share, another, done])
        footer.alignment = .center
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20)
        footer.backgroundColor = RDColor.background
        footer.translatesAutoresizingMaskIntoConstraints = false
        done.widthAnchor.constraint(equalTo: another.widthAnchor, multiplier: 1.3).isActive = true

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true
        let content = UIStackView(axis: .vertical, spacing: 8)
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20)
        let header = makeHeader()
        view.addSubview(scroll)
        view.addSubview(footer)
        scroll.addSubview(header)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            header.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        [makeMetricTiles(), makeCoachCard(), makeStreakCard()].forEach(content.addArrangedSubview)
    }

    private func makeHeader() -> UIView {
        let header = SlantedBottomView()
        header.backgroundColor = RDColor.neonGreen
        header.translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = UILabel()
        eyebrow.setEyebrow("SET COMPLETE · %@".rdLocalizedFormat(summary.exercise.displayName), color: RDColor.background, kern: 3)
        eyebrow.numberOfLines = 0
        let record = RDTag(text: "NEW RECORD", symbolName: "trophy.fill", background: RDColor.background, foreground: RDColor.ember)
        record.isHidden = !isNewRecord
        record.setContentHuggingPriority(.required, for: .horizontal)
        let top = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [eyebrow, UIView(), record])
        top.alignment = .center

        let count = RDNumberLabel()
        count.text = String(summary.repCount)
        count.font = RDFont.numeric(168, maximumScale: 1)
        count.textColor = RDColor.background
        count.adjustsFontSizeToFitWidth = true
        count.minimumScaleFactor = 0.5
        count.accessibilityLabel = "%d reps".rdLocalizedFormat(summary.repCount)
        let unit = UILabel()
        unit.text = "REPS_UNIT".rdLocalized
        unit.font = RDFont.title(22)
        unit.textColor = RDColor.background
        let best = UILabel()
        best.text = isNewRecord
            ? "Beat your best by %d".rdLocalizedFormat(summary.repCount - previousBest)
            : "Best %d reps".rdLocalizedFormat(stats.personalBest(for: summary.exercise))
        best.font = RDFont.caption(weight: .bold)
        best.textColor = RDColor.background
        best.numberOfLines = 0
        let unitStack = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [unit, best])
        let countRow = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [count, unitStack, UIView()])
        countRow.alignment = .lastBaseline

        let headline = UILabel()
        headline.text = (isNewRecord ? "New record. You're on fire." : "NICE WORK.").rdLocalized
        headline.font = RDFont.title(22)
        headline.textColor = RDColor.background
        headline.numberOfLines = 0
        headline.accessibilityTraits = .header

        [top, countRow, headline].forEach(headerStack.addArrangedSubview)
        headerStack.setCustomSpacing(10, after: countRow)
        if let rewards = summary.rewards, summary.repCount > 0 {
            headerStack.setCustomSpacing(16, after: headline)
            headerStack.addArrangedSubview(makeStars(rewards))
        }
        header.addSubview(headerStack)
        let headerTop = headerStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 60)
        self.headerTop = headerTop
        NSLayoutConstraint.activate([
            headerTop,
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -40)
        ])
        return header
    }

    /// Stars sit on the lime hero, so earned ones are solid black and the rest are outlines.
    private func makeStars(_ rewards: SetRewards) -> UIView {
        let configuration = UIImage.SymbolConfiguration(pointSize: 30, weight: .heavy)
        let stars = (0..<RepRewardTracker.maximumStars).map { index -> UIImageView in
            let lit = index < rewards.stars
            let star = UIImageView(image: UIImage(systemName: lit ? "star.fill" : "star", withConfiguration: configuration))
            star.tintColor = lit ? RDColor.background : RDColor.background.withAlphaComponent(0.35)
            return star
        }
        let row = UIStackView(axis: .horizontal, spacing: 6, arrangedSubviews: stars + [UIView()])
        row.isAccessibilityElement = true
        row.accessibilityLabel = "%d of 5 stars".rdLocalizedFormat(rewards.stars)

        let caption = UILabel()
        caption.text = "Best combo ×%1$d · %2$d perfect".rdLocalizedFormat(rewards.bestCombo, rewards.perfectCount)
        caption.font = RDFont.caption(weight: .bold)
        caption.textColor = RDColor.background
        caption.numberOfLines = 0

        let stack = UIStackView(axis: .vertical, spacing: 6, arrangedSubviews: [row, caption])
        stack.accessibilityIdentifier = "summary.stars"
        return stack
    }

    private func makeMetricTiles() -> UIView {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        let duration = RDStatTile(value: formatter.string(from: summary.activeDuration) ?? "0:00", caption: "Duration")
        let tempo = RDStatTile(
            value: summary.averageTempo.map { String(format: "%.1f", $0) } ?? "—",
            caption: "Sec / rep"
        )
        let heart = RDStatTile(
            value: summary.averageHeartRate.map { String(Int($0.rounded())) } ?? "—",
            caption: "Avg heart rate",
            valueColor: RDColor.ember
        )
        let row = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [duration, tempo, heart])
        row.distribution = .fillEqually
        return row
    }

    private func makeCoachCard() -> UIView {
        let card = UIView()
        card.backgroundColor = RDColor.surface
        card.layer.cornerRadius = RDCornerRadius.small
        card.isAccessibilityElement = true
        card.accessibilityIdentifier = "summary.aiCoach"
        let report = summary.coachingReport

        let ring = RDRingView()
        ring.lineWidth = 7
        ring.setProgress(CGFloat(report?.averageScore ?? 0) / 100, animated: false)
        let scoreText = report?.averageScore.map { String($0) } ?? "—"
        let scoreLabel = UILabel()
        scoreLabel.text = scoreText
        scoreLabel.font = RDFont.numeric(34, maximumScale: 1)
        scoreLabel.textColor = RDColor.warmWhite
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(scoreLabel)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 84),
            ring.heightAnchor.constraint(equalToConstant: 84),
            scoreLabel.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])

        let title = UILabel()
        title.setEyebrow("AI FORM COACH".rdLocalized, color: RDColor.neonGreen)
        let baseline = UILabel()
        baseline.text = (report?.isPersonalized == true ? "PERSONALIZED" : "LEARNING BASELINE").rdLocalized
        baseline.font = .systemFont(ofSize: 11, weight: .bold)
        baseline.textColor = RDColor.textSecondary
        let header = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [title, UIView(), baseline])
        header.alignment = .center
        let insightText = report?.insight ?? "Complete a set with clear tracking to unlock AI form feedback.".rdLocalized
        let insight = UILabel()
        insight.text = insightText
        insight.font = RDFont.body(weight: .bold)
        insight.textColor = RDColor.warmWhite
        insight.numberOfLines = 0
        insight.adjustsFontForContentSizeCategory = true
        let scoredValue = report.map {
            "%1$d OF %2$d SCORED".rdLocalizedFormat($0.scoredRepCount, max(summary.repCount, $0.scoredRepCount))
        } ?? "NO SCORED REPS".rdLocalized
        let goodValue = report.map { "%d GOOD REPS".rdLocalizedFormat($0.goodRepCount) } ?? ""
        let detail = UILabel()
        detail.text = [scoredValue, goodValue].filter { !$0.isEmpty }.joined(separator: " · ")
        detail.font = RDFont.caption(weight: .medium)
        detail.textColor = RDColor.textSecondary
        detail.numberOfLines = 0
        let texts = UIStackView(axis: .vertical, spacing: 8, arrangedSubviews: [header, insight, detail])
        let row = UIStackView(axis: .horizontal, spacing: 16, arrangedSubviews: [ring, texts])
        row.alignment = .center
        card.addSubview(row)
        row.pinEdges(to: card, insets: NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))

        card.accessibilityLabel = "AI form coach".rdLocalized
        card.accessibilityValue = "%1$@. %2$@. %3$@".rdLocalizedFormat(
            scoreText == "—" ? "No average score".rdLocalized : "%d out of 100".rdLocalizedFormat(report?.averageScore ?? 0),
            scoredValue,
            insightText
        )
        return card
    }

    private func makeStreakCard() -> UIView {
        let card = DashedBorderView()
        let flame = UIImageView(image: UIImage(
            systemName: "flame.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        ))
        flame.tintColor = RDColor.ember
        flame.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = "%d-day streak".rdLocalizedFormat(stats.streakDays)
        title.font = RDFont.body(weight: .black)
        title.textColor = RDColor.warmWhite
        title.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "%d reps this week".rdLocalizedFormat(stats.thisWeekReps)
        detail.font = RDFont.caption(weight: .regular)
        detail.textColor = RDColor.textSecondary
        detail.adjustsFontForContentSizeCategory = true
        let texts = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [title, detail])
        let row = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [flame, texts])
        row.alignment = .center
        card.addSubview(row)
        row.pinEdges(to: card, insets: NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        card.isAccessibilityElement = true
        card.accessibilityLabel = "\(title.text ?? ""), \(detail.text ?? "")"
        return card
    }
}

/// Lime header whose bottom edge cuts diagonally upward to the right.
private final class SlantedBottomView: UIView {
    private let shape = CAShapeLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: bounds.maxX, y: 0))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - 28))
        path.addLine(to: CGPoint(x: 0, y: bounds.maxY))
        path.close()
        shape.path = path.cgPath
        layer.mask = shape
    }
}

private final class DashedBorderView: UIView {
    private let border = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        border.strokeColor = RDColor.separatorStrong.cgColor
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 1.5
        border.lineDashPattern = [5, 4]
        layer.addSublayer(border)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.frame = bounds
        border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: RDCornerRadius.small).cgPath
    }
}
