import UIKit

final class ChooseViewController: RDBaseViewController {
    private let preferences: AppPreferences
    private let feedback: FeedbackService
    private let loadStats: () -> WorkoutStats
    private let squatCard = RDExerciseCard(exercise: .squat)
    private let pushUpCard = RDExerciseCard(exercise: .pushUp)
    private let streakNote = UILabel()
    private let goalRing = RDRingView()
    private let todayLabel = RDNumberLabel()
    private let goalLabel = UILabel()
    private let weekLabel = RDNumberLabel()
    private let weekDeltaLabel = UILabel()
    private let weekChart = RDBarChartView()
    private let lastSetCard = LastSetCard()
    private let startButton = RDPrimaryButton(title: "START SET")
    private var selectedExercise: ExerciseType
    private var stats: WorkoutStats?

    var onStart: ((ExerciseType) -> Void)?
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?

    init(preferences: AppPreferences, feedback: FeedbackService, loadStats: @escaping () -> WorkoutStats) {
        self.preferences = preferences
        self.feedback = feedback
        self.loadStats = loadStats
        self.selectedExercise = preferences.lastExercise
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderStats(loadStats())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Today".rdLocalized
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.hidesBackButton = true
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            primaryAction: UIAction { [weak self] _ in self?.onSettings?() }
        )
        settings.accessibilityLabel = "Settings".rdLocalized
        settings.accessibilityIdentifier = "choose.settings"
        let history = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            primaryAction: UIAction { [weak self] _ in self?.onHistory?() }
        )
        history.accessibilityLabel = "Workout history".rdLocalized
        history.accessibilityIdentifier = "choose.history"
        navigationItem.rightBarButtonItems = [settings, history]

        startButton.accessibilityIdentifier = "choose.start"
        startButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.start(self.selectedExercise)
        }, for: .touchUpInside)
        let (_, stack) = makeScrollableContent(pinnedFooter: makeFooter([startButton]))
        stack.spacing = 12

        let cards = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [squatCard, pushUpCard])
        cards.distribution = .fillEqually
        squatCard.accessibilityIdentifier = "choose.squat"
        pushUpCard.accessibilityIdentifier = "choose.pushUp"
        squatCard.addAction(UIAction { [weak self] _ in self?.select(.squat) }, for: .touchUpInside)
        pushUpCard.addAction(UIAction { [weak self] _ in self?.select(.pushUp) }, for: .touchUpInside)
        lastSetCard.accessibilityIdentifier = "choose.lastSet"
        lastSetCard.addAction(UIAction { [weak self] _ in
            guard let exercise = self?.stats?.lastSet?.exercise else { return }
            self?.select(exercise)
            self?.start(exercise)
        }, for: .touchUpInside)

        let pickHeader = makeEyebrow("Pick your move")
        pickHeader.directionalLayoutMargins = .zero

        [makeGoalCard(), makeWeekCard(), lastSetCard, pickHeader, cards].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(24, after: lastSetCard)
        stack.setCustomSpacing(8, after: pickHeader)
        renderSelection()
    }

    private func makeGoalCard() -> UIView {
        let card = makeCard()
        goalRing.lineWidth = 12
        todayLabel.font = RDFont.numeric(34)
        todayLabel.textColor = RDColor.accent
        goalLabel.font = RDFont.numeric(20, weight: .semibold)
        goalLabel.textColor = RDColor.secondaryLabel
        let countRow = UIStackView(axis: .horizontal, spacing: 4, arrangedSubviews: [todayLabel, goalLabel, UIView()])
        countRow.alignment = .firstBaseline
        streakNote.font = RDFont.caption(weight: .regular)
        streakNote.textColor = RDColor.secondaryLabel
        streakNote.numberOfLines = 0
        streakNote.adjustsFontForContentSizeCategory = true
        let labels = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [
            makeLabel(text: "Today's goal", font: .preferredFont(forTextStyle: .subheadline), color: RDColor.secondaryLabel),
            countRow,
            streakNote
        ])
        let row = UIStackView(axis: .horizontal, spacing: 16, arrangedSubviews: [goalRing, labels])
        row.alignment = .center
        card.addSubview(row)
        row.pinEdges(to: card, insets: NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        NSLayoutConstraint.activate([
            goalRing.widthAnchor.constraint(equalToConstant: 88),
            goalRing.heightAnchor.constraint(equalToConstant: 88)
        ])
        card.isAccessibilityElement = true
        goalRing.isAccessibilityElement = false
        goalCard = card
        return card
    }

    private func makeWeekCard() -> UIView {
        let card = makeCard()
        weekLabel.font = RDFont.numeric(17, weight: .semibold)
        weekLabel.textColor = RDColor.label
        weekDeltaLabel.font = .preferredFont(forTextStyle: .subheadline)
        weekDeltaLabel.textColor = RDColor.secondaryLabel
        weekDeltaLabel.adjustsFontForContentSizeCategory = true
        let header = UIStackView(axis: .horizontal, spacing: 6, arrangedSubviews: [
            makeLabel(text: "This week", font: RDFont.body(weight: .semibold)),
            UIView(),
            weekLabel,
            weekDeltaLabel
        ])
        header.alignment = .firstBaseline
        weekChart.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let stack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [header, weekChart])
        card.addSubview(stack)
        stack.pinEdges(to: card, insets: NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        return card
    }

    private var goalCard: UIView?

    private func renderStats(_ stats: WorkoutStats) {
        self.stats = stats
        let goal = preferences.dailyRepGoal
        let remaining = max(0, goal - stats.todayReps)
        let streak = stats.streakDays > 0 ? "%d-day streak".rdLocalizedFormat(stats.streakDays) : "No streak yet".rdLocalized
        let progress = remaining > 0 ? "%d to go".rdLocalizedFormat(remaining) : "Goal reached".rdLocalized
        streakNote.text = streak + " · " + progress

        todayLabel.text = String(stats.todayReps)
        goalLabel.text = "/ %d REPS".rdLocalizedFormat(goal)
        goalRing.setProgress(CGFloat(stats.todayReps) / CGFloat(goal), animated: true)
        goalCard?.accessibilityLabel = "Today's goal".rdLocalized
        goalCard?.accessibilityValue = "%1$d of %2$d reps".rdLocalizedFormat(stats.todayReps, goal) + ", " + (streakNote.text ?? "")

        weekLabel.text = String(stats.thisWeekReps)
        let delta = stats.thisWeekReps - stats.lastWeekReps
        weekDeltaLabel.text = "%@ vs last week".rdLocalizedFormat(delta >= 0 ? "+\(delta)" : "\(delta)")
        weekDeltaLabel.accessibilityLabel = weekDeltaLabel.text
        weekChart.render(values: stats.currentWeekDailyReps, labels: Self.weekdayLabels(), highlightIndex: stats.todayIndex)

        squatCard.setPersonalBest(stats.personalBest(for: .squat))
        pushUpCard.setPersonalBest(stats.personalBest(for: .pushUp))
        if let lastSet = stats.lastSet {
            lastSetCard.isHidden = false
            lastSetCard.render(lastSet)
        } else {
            lastSetCard.isHidden = true
        }
    }

    private static func weekdayLabels(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    private func start(_ exercise: ExerciseType) {
        preferences.lastExercise = exercise
        onStart?(exercise)
    }

    private func select(_ exercise: ExerciseType) {
        guard exercise != selectedExercise else { return renderSelection() }
        selectedExercise = exercise
        feedback.selectionChanged()
        renderSelection()
    }

    private func renderSelection() {
        squatCard.isSelected = selectedExercise == .squat
        pushUpCard.isSelected = selectedExercise == .pushUp
        startButton.configuration?.title = "Start a %@ set".rdLocalizedFormat(selectedExercise.displayName)
        startButton.accessibilityLabel = "Start a %@ set".rdLocalizedFormat(selectedExercise.displayName)
    }
}

/// "Do it again" shortcut built from the most recent saved set.
private final class LastSetCard: UIControl {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RDColor.card
        setContinuousCorners(RDCornerRadius.medium)
        titleLabel.font = RDFont.body(weight: .regular)
        titleLabel.textColor = RDColor.label
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = RDFont.caption(weight: .regular)
        detailLabel.textColor = RDColor.secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
        let icon = UIImageView(image: UIImage(
            systemName: "arrow.counterclockwise",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        ))
        icon.tintColor = RDColor.onAccent
        icon.backgroundColor = RDColor.accent
        icon.contentMode = .center
        icon.setContinuousCorners(RDCornerRadius.small)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ))
        chevron.tintColor = RDColor.tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let labels = UIStackView(axis: .vertical, spacing: 1, arrangedSubviews: [titleLabel, detailLabel])
        let row = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [icon, labels, chevron])
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        // List-row press feedback: a background highlight, never a scale.
        didSet { backgroundColor = isHighlighted ? RDColor.fill : RDColor.card }
    }

    func render(_ summary: WorkoutSummary) {
        titleLabel.text = "Another %@ set".rdLocalizedFormat(summary.exercise.displayName)
        let when = RelativeDateTimeFormatter().localizedString(for: summary.startedAt, relativeTo: Date())
        detailLabel.text = "%1$@ · %2$d reps".rdLocalizedFormat(when, summary.repCount)
        accessibilityLabel = titleLabel.text
        accessibilityValue = detailLabel.text
    }
}
