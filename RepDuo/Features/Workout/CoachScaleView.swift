import UIKit

final class CoachScaleView: UIView {
    private let headerLabel = UILabel()
    private let rangeRow = CoachMetricRow(title: "RANGE")
    private let tempoRow = CoachMetricRow(title: "TEMPO")
    private let symmetryRow = CoachMetricRow(title: "SYMMETRY")
    private let contentStack: UIStackView

    override init(frame: CGRect) {
        contentStack = UIStackView()
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.backgroundDeep.withAlphaComponent(0.88)
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = RDColor.separatorOnDark.withAlphaComponent(0.72).cgColor
        clipsToBounds = true

        headerLabel.text = "AI · —".rdLocalized
        headerLabel.textColor = RDColor.neonGreen
        headerLabel.font = .systemFont(ofSize: 19, weight: .black)
        headerLabel.adjustsFontSizeToFitWidth = true
        headerLabel.minimumScaleFactor = 0.72

        contentStack.axis = .vertical
        contentStack.spacing = 15
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [headerLabel, rangeRow, separator(), tempoRow, separator(), symmetryRow]
            .forEach(contentStack.addArrangedSubview)
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 14, bottom: 18, trailing: 14)
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
        contentStack.spacing = compact ? 7 : 15
        directionalLayoutMargins = compact
            ? NSDirectionalEdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11)
            : NSDirectionalEdgeInsets(top: 18, leading: 14, bottom: 18, trailing: 14)
        headerLabel.font = .systemFont(ofSize: compact ? 15 : 19, weight: .black)
        [rangeRow, tempoRow, symmetryRow].forEach { $0.setCompactLayout(compact) }
    }

    func render(_ result: RepCoachingResult?) {
        guard let result else {
            headerLabel.text = "AI · —".rdLocalized
            rangeRow.render(score: nil)
            tempoRow.render(score: nil)
            symmetryRow.render(score: nil)
            accessibilityValue = "Waiting for a clear repetition.".rdLocalized
            return
        }

        if let score = result.score {
            headerLabel.text = "AI · %d".rdLocalizedFormat(score)
        } else {
            headerLabel.text = "AI · —".rdLocalized
        }
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

    private func separator() -> UIView {
        let value = UIView()
        value.backgroundColor = RDColor.separatorOnDark.withAlphaComponent(0.72)
        value.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return value
    }
}

private final class CoachMetricRow: UIView {
    private let titleLabel = UILabel()
    private let scoreLabel = UILabel()
    private let track = UIView()
    private let fill = UIView()
    private var fillWidth: NSLayoutConstraint?
    private let labelsStack: UIStackView
    private let contentStack: UIStackView

    init(title: String) {
        labelsStack = UIStackView()
        contentStack = UIStackView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title.rdLocalized
        titleLabel.textColor = RDColor.textSecondary
        titleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72

        scoreLabel.textColor = RDColor.neonGreen
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .black)
        scoreLabel.adjustsFontSizeToFitWidth = true
        scoreLabel.minimumScaleFactor = 0.72

        track.backgroundColor = RDColor.separatorOnDark
        track.layer.cornerRadius = 3
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = RDColor.neonGreen
        fill.layer.cornerRadius = 3
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        labelsStack.axis = .vertical
        labelsStack.spacing = 2
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, scoreLabel].forEach(labelsStack.addArrangedSubview)
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        [labelsStack, track].forEach(contentStack.addArrangedSubview)
        addSubview(contentStack)
        contentStack.pinEdges(to: self)

        let width = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.01)
        fillWidth = width
        NSLayoutConstraint.activate([
            track.heightAnchor.constraint(equalToConstant: 6),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            width
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setCompactLayout(_ compact: Bool) {
        contentStack.spacing = compact ? 4 : 8
        labelsStack.spacing = compact ? 0 : 2
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: compact ? 17 : 23, weight: .black)
    }

    func render(score: Int?) {
        scoreLabel.text = score.map { String($0) } ?? "—"
        let color = (score ?? 100) < 80 ? RDColor.warning : RDColor.neonGreen
        scoreLabel.textColor = score == nil ? RDColor.textMuted : color
        fill.backgroundColor = color

        fillWidth?.isActive = false
        let progress = max(0.02, min(1, CGFloat(score ?? 0) / 100))
        let constraint = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: progress)
        constraint.isActive = true
        fillWidth = constraint
    }
}
