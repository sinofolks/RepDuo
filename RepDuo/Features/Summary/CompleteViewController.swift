import UIKit

final class CompleteViewController: UIViewController {
    private let summary: WorkoutSummary
    private let stats: WorkoutStats
    private let previousBest: Int
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RDColor.background
        navigationItem.hidesBackButton = true
        navigationItem.largeTitleDisplayMode = .never
        let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.onDone?() })
        done.accessibilityIdentifier = "summary.done"
        navigationItem.rightBarButtonItem = done

        let share = RDPrimaryButton(title: "Share result", symbolName: "square.and.arrow.up")
        share.accessibilityIdentifier = "summary.share"
        share.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onShare?(ShareCardContent(
                summary: self.summary,
                isNewRecord: self.isNewRecord,
                streakDays: self.stats.streakDays
            ))
        }, for: .touchUpInside)
        let another = RDPrimaryButton(title: "DO ANOTHER SET", style: .inverse)
        another.accessibilityIdentifier = "summary.another"
        another.addAction(UIAction { [weak self] _ in self?.onAnotherSet?() }, for: .touchUpInside)
        let footer = UIStackView(axis: .vertical, spacing: 10, arrangedSubviews: [share, another])
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16)
        footer.backgroundColor = RDColor.background
        footer.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        let content = UIStackView(axis: .vertical, spacing: 12)
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16)
        view.addSubview(scroll)
        view.addSubview(footer)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        let header = makeHeader()
        [header, makeMetricTiles(), makeCoachCard(), makeStreakCard()].forEach(content.addArrangedSubview)
        content.setCustomSpacing(24, after: header)
    }

    private func makeHeader() -> UIView {
        let eyebrow = UILabel()
        eyebrow.text = "%@ · set complete".rdLocalizedFormat(summary.exercise.displayName)
        eyebrow.font = .preferredFont(forTextStyle: .subheadline)
        eyebrow.adjustsFontForContentSizeCategory = true
        eyebrow.textColor = RDColor.secondaryLabel
        eyebrow.numberOfLines = 0
        eyebrow.textAlignment = .center

        let count = RDNumberLabel()
        count.text = String(summary.repCount)
        count.font = RDFont.numeric(96, maximumScale: 1)
        count.textColor = RDColor.label
        count.textAlignment = .center
        count.accessibilityLabel = "%d reps".rdLocalizedFormat(summary.repCount)

        let detail = isNewRecord
            ? "New record · +%d".rdLocalizedFormat(summary.repCount - previousBest)
            : "Best %d reps".rdLocalizedFormat(stats.personalBest(for: summary.exercise))
        let tag = RDTag(text: detail, symbolName: isNewRecord ? "star.fill" : nil)
        if !isNewRecord { tag.setColors(background: RDColor.fill, foreground: RDColor.secondaryLabel) }
        tag.accessibilityTraits = .header

        let stack = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [eyebrow, count, tag])
        stack.alignment = .center
        stack.setCustomSpacing(8, after: count)
        if let rewards = summary.rewards, summary.repCount > 0 {
            stack.setCustomSpacing(16, after: tag)
            stack.addArrangedSubview(makeStars(rewards))
        }
        return stack
    }

    private func makeStars(_ rewards: SetRewards) -> UIView {
        let configuration = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        let stars = (0..<RepRewardTracker.maximumStars).map { index -> UIImageView in
            let lit = index < rewards.stars
            let star = UIImageView(image: UIImage(systemName: lit ? "star.fill" : "star", withConfiguration: configuration))
            star.tintColor = lit ? RDColor.reward : RDColor.tertiaryLabel
            return star
        }
        let row = UIStackView(axis: .horizontal, spacing: 6, arrangedSubviews: stars)
        row.isAccessibilityElement = true
        row.accessibilityLabel = "%d of 5 stars".rdLocalizedFormat(rewards.stars)

        let caption = UILabel()
        caption.text = "Best combo ×%1$d · %2$d perfect".rdLocalizedFormat(rewards.bestCombo, rewards.perfectCount)
        caption.font = .preferredFont(forTextStyle: .footnote)
        caption.adjustsFontForContentSizeCategory = true
        caption.textColor = RDColor.secondaryLabel
        caption.textAlignment = .center
        caption.numberOfLines = 0

        let stack = UIStackView(axis: .vertical, spacing: 6, arrangedSubviews: [row, caption])
        stack.alignment = .center
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
            caption: "Avg heart rate"
        )
        let row = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [duration, tempo, heart])
        row.distribution = .fillEqually
        return row
    }

    private func makeCoachCard() -> UIView {
        let card = UIView()
        card.backgroundColor = RDColor.card
        card.setContinuousCorners(RDCornerRadius.medium)
        card.isAccessibilityElement = true
        card.accessibilityIdentifier = "summary.aiCoach"
        let report = summary.coachingReport

        let ring = RDRingView()
        ring.lineWidth = 6
        ring.setProgress(CGFloat(report?.averageScore ?? 0) / 100, animated: false)
        let scoreText = report?.averageScore.map { String($0) } ?? "—"
        let scoreLabel = UILabel()
        scoreLabel.text = scoreText
        scoreLabel.font = RDFont.numeric(20, maximumScale: 1)
        scoreLabel.textColor = RDColor.label
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(scoreLabel)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 56),
            ring.heightAnchor.constraint(equalToConstant: 56),
            scoreLabel.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])

        let title = UILabel()
        title.text = "AI form coach".rdLocalized
        title.font = RDFont.body(weight: .semibold)
        title.textColor = RDColor.label
        let baseline = UILabel()
        baseline.text = (report?.isPersonalized == true ? "PERSONALIZED" : "LEARNING BASELINE").rdLocalized
        baseline.font = .preferredFont(forTextStyle: .caption1)
        baseline.textColor = RDColor.secondaryLabel
        let header = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [title, UIView(), baseline])
        header.alignment = .center
        let insightText = report?.insight ?? "Complete a set with clear tracking to unlock AI form feedback.".rdLocalized
        let insight = UILabel()
        insight.text = insightText
        insight.font = .preferredFont(forTextStyle: .subheadline)
        insight.textColor = RDColor.secondaryLabel
        insight.numberOfLines = 0
        insight.adjustsFontForContentSizeCategory = true
        let scoredValue = report.map {
            "%1$d OF %2$d SCORED".rdLocalizedFormat($0.scoredRepCount, max(summary.repCount, $0.scoredRepCount))
        } ?? "NO SCORED REPS".rdLocalized
        let goodValue = report.map { "%d GOOD REPS".rdLocalizedFormat($0.goodRepCount) } ?? ""
        let detail = UILabel()
        detail.text = [scoredValue, goodValue].filter { !$0.isEmpty }.joined(separator: " · ")
        detail.font = RDFont.caption(weight: .regular)
        detail.textColor = RDColor.secondaryLabel
        detail.numberOfLines = 0
        let texts = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [header, insight, detail])
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
        let card = UIView()
        card.backgroundColor = RDColor.card
        card.setContinuousCorners(RDCornerRadius.medium)
        let flame = UIImageView(image: UIImage(
            systemName: "flame.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        ))
        flame.tintColor = RDColor.accent
        flame.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = "%d-day streak".rdLocalizedFormat(stats.streakDays)
        title.font = RDFont.body(weight: .regular)
        title.textColor = RDColor.label
        title.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        detail.text = "%d reps this week".rdLocalizedFormat(stats.thisWeekReps)
        detail.font = RDFont.caption(weight: .regular)
        detail.textColor = RDColor.secondaryLabel
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
