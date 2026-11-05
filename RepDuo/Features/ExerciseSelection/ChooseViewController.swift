import UIKit

final class ChooseViewController: RDBaseViewController {
    private let preferences: AppPreferences
    private let feedback: FeedbackService
    private let loadStats: () -> WorkoutStats
    private let exerciseCards = ExerciseType.allCases.map(RDExerciseCard.init(exercise:))
    private let streakTag = RDTag(symbolName: "flame.fill", background: RDColor.ember)
    private let streakNote = UILabel()
    private let goalMeter = RDGoalMeterView()
    private let goalPercentLabel = UILabel()
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

        for card in exerciseCards {
            card.accessibilityIdentifier = "choose.\(card.exercise.rawValue)"
            card.addAction(UIAction { [weak self] _ in self?.select(card.exercise) }, for: .touchUpInside)
        }
        // Two-column grid; an odd last card keeps its half width.
        let rows = stride(from: 0, to: exerciseCards.count, by: 2).map { index -> UIStackView in
            let pair: [UIView] = Array(exerciseCards[index..<min(index + 2, exerciseCards.count)])
            let row = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: pair.count == 2 ? pair : pair + [UIView()])
            row.distribution = .fillEqually
            return row
        }
        let cards = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: rows)
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

    /// Scoreboard panel: today's count against the goal on a segmented meter,
    /// then the week's total beside the daily bars.
    private func makeHero() -> UIView {
        todayLabel.font = RDFont.numeric(64)
        todayLabel.textColor = RDColor.warmWhite
        goalLabel.font = RDFont.numeric(20, weight: .heavy)
        goalLabel.textColor = RDColor.textSecondary
        goalPercentLabel.font = RDFont.numeric(20, weight: .heavy, italic: false)
        goalPercentLabel.textAlignment = .right
        let todayHeader = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [
            makeEyebrow("TODAY'S GOAL", color: RDColor.neonGreen), UIView(), goalPercentLabel
        ])
        todayHeader.alignment = .firstBaseline
        let todayRow = UIStackView(axis: .horizontal, spacing: 4, arrangedSubviews: [todayLabel, goalLabel, UIView()])
        todayRow.alignment = .lastBaseline
        goalMeter.isAccessibilityElement = true

        let divider = UIView()
        divider.backgroundColor = RDColor.separatorOnDark
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        weekLabel.font = RDFont.numeric(40)
        weekLabel.textColor = RDColor.warmWhite
        weekDeltaLabel.font = RDFont.numeric(16, weight: .heavy, italic: false)
        let weekTotals = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [
            makeEyebrow("THIS WEEK"), weekLabel, weekDeltaLabel
        ])
        weekTotals.alignment = .leading
        weekTotals.setContentHuggingPriority(.required, for: .horizontal)
        weekChart.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let weekRow = UIStackView(axis: .horizontal, spacing: 20, arrangedSubviews: [weekTotals, weekChart])
        weekRow.alignment = .bottom
        weekChart.widthAnchor.constraint(equalTo: weekRow.widthAnchor, multiplier: 0.62).isActive = true

        let content = UIStackView(axis: .vertical, spacing: 4, arrangedSubviews: [todayHeader, todayRow, goalMeter, divider, weekRow])
        content.setCustomSpacing(10, after: todayRow)
        content.setCustomSpacing(18, after: goalMeter)
        content.setCustomSpacing(16, after: divider)
        let panel = UIView()
        panel.backgroundColor = RDColor.surface
        panel.layer.cornerRadius = RDCornerRadius.small
        panel.addSubview(content)
        content.pinEdges(to: panel, insets: NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        return panel
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
        let progress = CGFloat(stats.todayReps) / CGFloat(max(goal, 1))
        let meterColor = stats.todayReps >= goal ? RDColor.ember : RDColor.neonGreen
        goalMeter.render(progress: progress, color: meterColor)
        goalPercentLabel.text = "\(Int(min(progress, 1) * 100))%"
        goalPercentLabel.textColor = meterColor
        goalMeter.accessibilityLabel = "Today's goal".rdLocalized
        goalMeter.accessibilityValue = "%1$d of %2$d reps".rdLocalizedFormat(stats.todayReps, goal)

        weekLabel.text = String(stats.thisWeekReps)
        let delta = stats.thisWeekReps - stats.lastWeekReps
        weekDeltaLabel.text = delta >= 0 ? "▲ \(delta)" : "▼ \(-delta)"
        weekDeltaLabel.textColor = delta >= 0 ? RDColor.neonGreen : RDColor.textMuted
        weekDeltaLabel.accessibilityLabel = "%d vs last week".rdLocalizedFormat(delta)
        weekChart.render(values: stats.currentWeekDailyReps, labels: Self.weekdayLabels(), highlightIndex: stats.todayIndex)

        exerciseCards.forEach { $0.setPersonalBest(stats.personalBest(for: $0.exercise)) }
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
        exerciseCards.forEach { $0.isSelected = $0.exercise == selectedExercise }
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

/// Ten slanted segments that light up toward the daily goal.
private final class RDGoalMeterView: UIView {
    private static let segmentCount = 10
    private let segments = (0..<RDGoalMeterView.segmentCount).map { _ in RDSlantedBlockView(slant: 6) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let row = UIStackView(axis: .horizontal, spacing: 4, arrangedSubviews: segments)
        row.distribution = .fillEqually
        addSubview(row)
        row.pinEdges(to: self)
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    func render(progress: CGFloat, color: UIColor) {
        // Any rep lights the first segment so a started day never reads as empty.
        let lit = progress > 0 ? max(1, Int((min(progress, 1) * CGFloat(Self.segmentCount)).rounded(.down))) : 0
        for (index, segment) in segments.enumerated() {
            segment.fillColor = index < lit ? color : RDColor.surfaceSecondary
        }
    }
}
