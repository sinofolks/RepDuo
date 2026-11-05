import UIKit

final class ChooseViewController: RDBaseViewController {
    private let preferences: AppPreferences
    private let feedback: FeedbackService
    private let loadStats: () -> WorkoutStats
    private let squatCard = RDExerciseCard(exercise: .squat)
    private let pushUpCard = RDExerciseCard(exercise: .pushUp)
    private let streakTag = RDTag(symbolName: "flame.fill", background: RDColor.ember)
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
        navigationController?.setNavigationBarHidden(true, animated: animated)
        renderStats(loadStats())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true

        startButton.accessibilityIdentifier = "choose.start"
        startButton.configuration?.titleTextAttributesTransformer = nil
        startButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        startButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        startButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.start(self.selectedExercise)
        }, for: .touchUpInside)
        let (_, stack) = makeScrollableContent(pinnedFooter: makeFooter([startButton]))
        stack.spacing = 18

        let history = RDIconButton(symbolName: "clock.arrow.circlepath", accessibilityLabel: "Workout history")
        history.accessibilityIdentifier = "choose.history"
        history.addAction(UIAction { [weak self] _ in self?.onHistory?() }, for: .touchUpInside)
        let settings = RDIconButton(symbolName: "slider.horizontal.3", accessibilityLabel: "Settings")
        settings.accessibilityIdentifier = "choose.settings"
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
        let header = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [RDWordmarkView(), UIView(), history, settings])
        header.alignment = .center

        streakNote.font = RDFont.caption(weight: .regular)
        streakNote.textColor = RDColor.textSecondary
        streakNote.numberOfLines = 0
        streakNote.adjustsFontForContentSizeCategory = true
        let streakRow = UIStackView(axis: .horizontal, spacing: 10, arrangedSubviews: [streakTag, streakNote])
        streakRow.alignment = .center
        streakTag.setContentHuggingPriority(.required, for: .horizontal)
        streakTag.setContentCompressionResistancePriority(.required, for: .horizontal)

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

        let pickHeader = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [
            makeEyebrow("PICK YOUR MOVE"),
            UIView(),
            makeLabel(text: "Tap to choose", font: RDFont.caption(weight: .regular), color: RDColor.textMuted)
        ])
        pickHeader.alignment = .firstBaseline

        [header, streakRow, makeHero(), lastSetCard, pickHeader, cards].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(10, after: pickHeader)
        renderSelection()
    }

    private func makeHero() -> UIView {
        goalRing.lineWidth = 14
        todayLabel.font = RDFont.numeric(64)
        todayLabel.textColor = RDColor.warmWhite
        todayLabel.adjustsFontSizeToFitWidth = true
        todayLabel.minimumScaleFactor = 0.6
        todayLabel.textAlignment = .center
        goalLabel.font = RDFont.numeric(16, weight: .bold, italic: false)
        goalLabel.textColor = RDColor.textSecondary
        let goalCaption = makeLabel(text: "TODAY'S GOAL", font: .systemFont(ofSize: 12, weight: .bold), color: RDColor.neonGreen)
        let ringCenter = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [todayLabel, goalLabel, goalCaption])
        ringCenter.alignment = .center
        ringCenter.setCustomSpacing(2, after: goalLabel)
        goalRing.addSubview(ringCenter)
        ringCenter.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            goalRing.widthAnchor.constraint(equalToConstant: 168),
            goalRing.heightAnchor.constraint(equalToConstant: 168),
            ringCenter.centerXAnchor.constraint(equalTo: goalRing.centerXAnchor),
            ringCenter.centerYAnchor.constraint(equalTo: goalRing.centerYAnchor),
            ringCenter.widthAnchor.constraint(lessThanOrEqualToConstant: 120)
        ])
        goalRing.isAccessibilityElement = true

        weekLabel.font = RDFont.numeric(48)
        weekLabel.textColor = RDColor.warmWhite
        weekDeltaLabel.font = RDFont.numeric(16, weight: .heavy, italic: false)
        let weekRow = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [weekLabel, weekDeltaLabel, UIView()])
        weekRow.alignment = .firstBaseline
        weekChart.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let week = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [
            makeLabel(text: "THIS WEEK", font: .systemFont(ofSize: 12, weight: .bold), color: RDColor.textSecondary),
            weekRow,
            weekChart
        ])
        week.setCustomSpacing(8, after: weekRow)
        let hero = UIStackView(axis: .horizontal, spacing: 20, arrangedSubviews: [goalRing, week])
        hero.alignment = .center
        return hero
    }

    private func renderStats(_ stats: WorkoutStats) {
        self.stats = stats
        if stats.streakDays > 0 {
            streakTag.text = "%d-day streak".rdLocalizedFormat(stats.streakDays)
            streakTag.setColors(background: RDColor.ember, foreground: RDColor.background)
        } else {
            streakTag.text = "No streak yet".rdLocalized
            streakTag.setColors(background: RDColor.surfaceSecondary, foreground: RDColor.warmWhite)
        }
        if stats.trainedToday {
            streakNote.text = "%d sets done today · keep it going".rdLocalizedFormat(stats.setsToday)
        } else if stats.streakDays > 0 {
            streakNote.text = "No reps yet today · keep the fire".rdLocalized
        } else {
            streakNote.text = "One set today starts a streak".rdLocalized
        }

        let goal = preferences.dailyRepGoal
        todayLabel.text = String(stats.todayReps)
        goalLabel.text = "/ %d REPS".rdLocalizedFormat(goal)
        goalRing.setProgress(CGFloat(stats.todayReps) / CGFloat(goal), animated: true)
        goalRing.progressColor = stats.todayReps >= goal ? RDColor.ember : RDColor.neonGreen
        goalRing.accessibilityLabel = "Today's goal".rdLocalized
        goalRing.accessibilityValue = "%1$d of %2$d reps".rdLocalizedFormat(stats.todayReps, goal)

        weekLabel.text = String(stats.thisWeekReps)
        let delta = stats.thisWeekReps - stats.lastWeekReps
        weekDeltaLabel.text = delta >= 0 ? "▲ \(delta)" : "▼ \(-delta)"
        weekDeltaLabel.textColor = delta >= 0 ? RDColor.neonGreen : RDColor.textMuted
        weekDeltaLabel.accessibilityLabel = "%d vs last week".rdLocalizedFormat(delta)
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
        let title = NSMutableAttributedString(string: "GO", attributes: [
            .font: RDFont.numeric(38, maximumScale: 1.1),
            .kern: 1
        ])
        title.append(NSAttributedString(
            string: "   " + "Start a %@ set".rdLocalizedFormat(selectedExercise.displayName),
            attributes: [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(
                for: .systemFont(ofSize: 18, weight: .black),
                maximumPointSize: 24
            )]
        ))
        startButton.configuration?.attributedTitle = AttributedString(title)
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
        backgroundColor = RDColor.surface
        layer.cornerRadius = RDCornerRadius.small
        let eyebrow = UILabel()
        eyebrow.setEyebrow("AGAIN · LAST SET".rdLocalized, kern: 1.5)
        eyebrow.font = RDFont.eyebrow(12)
        titleLabel.font = RDFont.body(weight: .black)
        titleLabel.textColor = RDColor.warmWhite
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = RDFont.caption(weight: .regular)
        detailLabel.textColor = RDColor.textSecondary
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
        let play = UIImageView(image: UIImage(
            systemName: "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        ))
        play.tintColor = RDColor.background
        play.backgroundColor = RDColor.neonGreen
        play.contentMode = .center
        play.layer.cornerRadius = 24
        play.translatesAutoresizingMaskIntoConstraints = false
        let labels = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [eyebrow, titleLabel, detailLabel])
        let row = UIStackView(axis: .horizontal, spacing: 14, arrangedSubviews: [labels, play])
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
        NSLayoutConstraint.activate([
            play.widthAnchor.constraint(equalToConstant: 48),
            play.heightAnchor.constraint(equalToConstant: 48)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { nil }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : 1 }
    }

    func render(_ summary: WorkoutSummary) {
        titleLabel.text = "Another %@ set".rdLocalizedFormat(summary.exercise.displayName)
        let when = RelativeDateTimeFormatter().localizedString(for: summary.startedAt, relativeTo: Date())
        detailLabel.text = "%1$@ · %2$d reps".rdLocalizedFormat(when, summary.repCount)
        accessibilityLabel = titleLabel.text
        accessibilityValue = detailLabel.text
    }
}
