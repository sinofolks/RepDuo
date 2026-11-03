import UIKit

final class CompleteViewController: UIViewController {
    private let summary: WorkoutSummary
    var onDone: (() -> Void)?
    var onAnotherSet: (() -> Void)?

    init(summary: WorkoutSummary) {
        self.summary = summary
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RDColor.warmWhite
        navigationItem.hidesBackButton = true
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(axis: .vertical, spacing: RDSpacing.lg)
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: RDSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -RDSpacing.lg),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: RDSpacing.xl),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -RDSpacing.lg),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * RDSpacing.lg)
        ])

        let wordmark = RDWordmarkView(surface: .light)
        let eyebrow = label("SET COMPLETE", font: RDFont.caption(), color: RDColor.background)
        let title = label("NICE WORK.", font: RDFont.display(42), color: RDColor.background)
        title.accessibilityTraits = .header
        let subtitle = label("One strong set. Keep the rhythm.", font: RDFont.body(), color: RDColor.textMuted)
        let check = UIImageView(image: UIImage(systemName: "checkmark"))
        check.tintColor = RDColor.background
        check.backgroundColor = RDColor.neonGreen
        check.contentMode = .center
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        check.layer.cornerRadius = 90
        check.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            check.widthAnchor.constraint(equalToConstant: 180),
            check.heightAnchor.constraint(equalToConstant: 180)
        ])
        let checkContainer = UIView()
        checkContainer.addSubview(check)
        NSLayoutConstraint.activate([
            check.centerXAnchor.constraint(equalTo: checkContainer.centerXAnchor),
            check.topAnchor.constraint(equalTo: checkContainer.topAnchor),
            check.bottomAnchor.constraint(equalTo: checkContainer.bottomAnchor)
        ])

        let metrics = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: metricRows())
        metrics.arrangedSubviews.dropLast().forEach { row in
            let line = UIView()
            line.backgroundColor = RDColor.separator
            line.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                line.heightAnchor.constraint(equalToConstant: 1)
            ])
        }
        let coachCard = makeCoachCard()

        let done = RDPrimaryButton(title: "DONE")
        done.configuration?.baseBackgroundColor = RDColor.background
        done.configuration?.baseForegroundColor = RDColor.warmWhite
        done.accessibilityIdentifier = "summary.done"
        done.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        let another = UIButton(type: .system)
        another.setTitle("DO ANOTHER SET".rdLocalized, for: .normal)
        another.setTitleColor(RDColor.background, for: .normal)
        another.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        another.addAction(UIAction { [weak self] _ in self?.onAnotherSet?() }, for: .touchUpInside)

        [wordmark, eyebrow, title, subtitle, checkContainer, metrics, coachCard, done, another].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(2, after: eyebrow)
        stack.setCustomSpacing(8, after: title)
    }

    private func metricRows() -> [UIView] {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        let duration = formatter.string(from: summary.activeDuration) ?? "0:00"
        var rows: [UIView] = [
            RDSummaryMetricRow(label: "Reps", value: String(summary.repCount)),
            RDSummaryMetricRow(label: "Duration", value: duration),
            RDSummaryMetricRow(label: "Move", value: summary.exercise.displayName)
        ]
        if let averageTempo = summary.averageTempo {
            rows.append(RDSummaryMetricRow(label: "Avg tempo", value: "%.1f SEC/REP".rdLocalizedFormat(averageTempo)))
        }
        if let average = summary.averageHeartRate {
            rows.append(RDSummaryMetricRow(label: "Avg heart rate", value: "%d BPM".rdLocalizedFormat(Int(average.rounded()))))
        }
        if let maximum = summary.maximumHeartRate {
            rows.append(RDSummaryMetricRow(label: "Max heart rate", value: "%d BPM".rdLocalizedFormat(Int(maximum.rounded()))))
        }
        if summary.lowConfidenceEventCount > 0 {
            rows.append(RDSummaryMetricRow(
                label: "Tracking adjustments",
                value: String(summary.lowConfidenceEventCount)
            ))
        }
        return rows
    }

    private func makeCoachCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = RDColor.background
        card.layer.cornerRadius = RDCornerRadius.large
        card.layer.borderWidth = 1
        card.layer.borderColor = RDColor.separatorOnDark.cgColor
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        card.isAccessibilityElement = true
        card.accessibilityIdentifier = "summary.aiCoach"

        let title = label("AI FORM COACH", font: .systemFont(ofSize: 12, weight: .black), color: RDColor.neonGreen)
        let baseline = label(
            summary.coachingReport?.isPersonalized == true ? "PERSONALIZED" : "LEARNING BASELINE",
            font: .systemFont(ofSize: 10, weight: .bold),
            color: RDColor.textSecondary
        )
        baseline.textAlignment = .right
        let header = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [title, baseline])
        header.distribution = .equalSpacing

        let score = summary.coachingReport?.averageScore.map { String($0) } ?? "—"
        let scoreLabel = label(score, font: RDFont.display(54), color: RDColor.warmWhite)
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = 0.72
        let scoreCaption = label("AVERAGE FORM SCORE", font: .systemFont(ofSize: 10, weight: .bold), color: RDColor.textSecondary)
        let scoreStack = UIStackView(axis: .vertical, spacing: -2, arrangedSubviews: [scoreLabel, scoreCaption])

        let report = summary.coachingReport
        let scoredValue = report.map {
            "%1$d OF %2$d SCORED".rdLocalizedFormat($0.scoredRepCount, max(summary.repCount, $0.scoredRepCount))
        } ?? "NO SCORED REPS".rdLocalized
        let goodValue = report.map { "%d GOOD REPS".rdLocalizedFormat($0.goodRepCount) } ?? "—"
        let scored = compactStat(scoredValue)
        let good = compactStat(goodValue)
        let stats = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [scored, good])
        stats.distribution = .fillEqually

        let insight = label(
            report?.insight ?? "Complete a set with clear tracking to unlock AI form feedback.",
            font: RDFont.body(weight: .semibold),
            color: RDColor.warmWhite
        )

        let stack = UIStackView(axis: .vertical, spacing: 16, arrangedSubviews: [header, scoreStack, stats, insight])
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.layoutMarginsGuide.bottomAnchor)
        ])

        card.accessibilityLabel = "AI form coach".rdLocalized
        card.accessibilityValue = "%1$@. %2$@. %3$@".rdLocalizedFormat(
            score == "—" ? "No average score".rdLocalized : "%d out of 100".rdLocalizedFormat(report?.averageScore ?? 0),
            scoredValue,
            report?.insight ?? "Complete a set with clear tracking to unlock AI form feedback.".rdLocalized
        )
        return card
    }

    private func compactStat(_ text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = RDColor.surface
        container.layer.cornerRadius = RDCornerRadius.small
        let value = label(text, font: .systemFont(ofSize: 11, weight: .black), color: RDColor.neonGreen)
        value.textAlignment = .center
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.72
        container.addSubview(value)
        value.pinEdges(
            to: container,
            insets: NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        )
        return container
    }

    private func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let value = UILabel()
        value.text = text.rdLocalized
        value.font = font
        value.textColor = color
        value.numberOfLines = 0
        value.adjustsFontForContentSizeCategory = true
        return value
    }

}
