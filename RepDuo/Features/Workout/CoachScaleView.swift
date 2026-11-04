import UIKit

/// Live AI form score: the overall score followed by range, tempo, and symmetry bars in one row.
final class CoachScaleView: UIView {
    private let scoreLabel = UILabel()
    private let rangeRow = CoachMetricColumn(title: "RANGE")
    private let tempoRow = CoachMetricColumn(title: "TEMPO")
    private let symmetryRow = CoachMetricColumn(title: "SYMMETRY")
    private let contentStack = UIStackView(axis: .horizontal, spacing: 14)

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.surface.withAlphaComponent(0.94)
        layer.cornerRadius = RDCornerRadius.medium

        let caption = UILabel()
        caption.setEyebrow("AI SCORE".rdLocalized, kern: 1.5)
        caption.font = RDFont.eyebrow(12)
        scoreLabel.font = RDFont.numeric(36, maximumScale: 1.1)
        scoreLabel.textColor = RDColor.warmWhite
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = 0.7
        let score = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [caption, scoreLabel])
        score.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let metrics = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [rangeRow, tempoRow, symmetryRow])
        metrics.distribution = .fillEqually
        [score, metrics].forEach(contentStack.addArrangedSubview)
        contentStack.alignment = .center
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "workout.coachScale"
        accessibilityLabel = "AI form coach".rdLocalized
        render(nil)
    }

    required init?(coder: NSCoder) { nil }

    func setCompactLayout(_ compact: Bool) {
        directionalLayoutMargins = compact
            ? NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            : NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    }

    /// Latest overall score, or nil before the first scored rep.
    private(set) var currentScore: Int?

    func render(_ result: RepCoachingResult?) {
        guard let result else {
            currentScore = nil
            scoreLabel.text = "—"
            rangeRow.render(score: nil)
            tempoRow.render(score: nil)
            symmetryRow.render(score: nil)
            accessibilityValue = "Waiting for a clear repetition.".rdLocalized
            return
        }

        currentScore = result.score
        scoreLabel.text = result.score.map { String($0) } ?? "—"
        rangeRow.render(score: result.rangeScore)
        tempoRow.render(score: result.tempoScore)
        symmetryRow.render(score: result.symmetryScore)

        let personalization = result.isPersonalized
            ? "Personalized".rdLocalized
            : "Learning %d of 3".rdLocalizedFormat(result.baselineProgress)
        if let score = result.score {
            accessibilityValue = "%1$@, score %2$d out of 100. %3$@".rdLocalizedFormat(
                personalization,
                score,
                result.primaryIssue?.liveCue ?? "Good form. Keep this rhythm.".rdLocalized
            )
        } else {
            accessibilityValue = "%1$@. %2$@".rdLocalizedFormat(
                personalization,
                "Rep counted, but visibility was too low to score it.".rdLocalized
            )
        }
    }
}

private final class CoachMetricColumn: UIView {
    private let titleLabel = UILabel()
    private let scoreLabel = UILabel()
    private let track = UIView()
    private let fill = UIView()
    private var fillWidth: NSLayoutConstraint?

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title.rdLocalized
        titleLabel.textColor = RDColor.textBody
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        scoreLabel.font = RDFont.numeric(16, weight: .heavy, italic: false, maximumScale: 1.1)
        scoreLabel.textAlignment = .right
        scoreLabel.setContentHuggingPriority(.required, for: .horizontal)

        track.backgroundColor = RDColor.separatorOnDark
        track.layer.cornerRadius = 2
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.layer.cornerRadius = 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        let header = UIStackView(axis: .horizontal, spacing: 4, arrangedSubviews: [titleLabel, scoreLabel])
        header.alignment = .firstBaseline
        let stack = UIStackView(axis: .vertical, spacing: 6, arrangedSubviews: [header, track])
        addSubview(stack)
        stack.pinEdges(to: self)

        let width = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.01)
        fillWidth = width
        NSLayoutConstraint.activate([
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            width
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(score: Int?) {
        scoreLabel.text = score.map { String($0) } ?? "—"
        let color = (score ?? 100) < 80 ? RDColor.warning : RDColor.neonGreen
        scoreLabel.textColor = score == nil ? RDColor.textMuted : ((score ?? 100) < 80 ? RDColor.warning : RDColor.warmWhite)
        fill.backgroundColor = color

        fillWidth?.isActive = false
        let progress = max(0.02, min(1, CGFloat(score ?? 0) / 100))
        let constraint = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: progress)
        constraint.isActive = true
        fillWidth = constraint
    }
}
