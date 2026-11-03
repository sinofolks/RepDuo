import UIKit

final class ChooseViewController: RDBaseViewController {
    private let preferences: AppPreferences
    private let feedback: FeedbackService
    private let squatCard = RDExerciseCard(exercise: .squat)
    private let pushUpCard = RDExerciseCard(exercise: .pushUp)
    private var selectedExercise: ExerciseType

    var onStart: ((ExerciseType) -> Void)?
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?

    init(preferences: AppPreferences, feedback: FeedbackService) {
        self.preferences = preferences
        self.feedback = feedback
        self.selectedExercise = preferences.lastExercise
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "clock.arrow.circlepath"),
            primaryAction: UIAction { [weak self] _ in self?.onHistory?() }
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Workout history".rdLocalized
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            primaryAction: UIAction { [weak self] _ in self?.onSettings?() }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Settings".rdLocalized

        let (_, stack) = makeScrollableContent()
        let wordmark = RDWordmarkView()
        let eyebrow = makeLabel(text: "READY TO MOVE?", font: RDFont.caption(), color: RDColor.textSecondary)
        let title = makeLabel(text: "CHOOSE.\nSTART.", font: RDFont.display(46))
        title.accessibilityTraits = .header
        let hint = makeLabel(
            text: "Pick one focused movement. RepDuo will handle the count.",
            font: RDFont.body(),
            color: RDColor.textSecondary
        )
        let cards = UIStackView(axis: .horizontal, spacing: 12, arrangedSubviews: [squatCard, pushUpCard])
        cards.distribution = .fillEqually
        squatCard.accessibilityIdentifier = "choose.squat"
        pushUpCard.accessibilityIdentifier = "choose.pushUp"
        squatCard.addAction(UIAction { [weak self] _ in self?.select(.squat) }, for: .touchUpInside)
        pushUpCard.addAction(UIAction { [weak self] _ in self?.select(.pushUp) }, for: .touchUpInside)

        let streak = RDStatusPill(text: "Ready for your next set", positive: true)
        let start = RDPrimaryButton(title: "START SET", symbolName: "arrow.right")
        start.accessibilityIdentifier = "choose.start"
        start.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.preferences.lastExercise = self.selectedExercise
            self.onStart?(self.selectedExercise)
        }, for: .touchUpInside)

        [wordmark, eyebrow, title, hint, streak, cards, start].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(2, after: eyebrow)
        renderSelection()
    }

    private func select(_ exercise: ExerciseType) {
        selectedExercise = exercise
        feedback.selectionChanged()
        renderSelection()
    }

    private func renderSelection() {
        squatCard.isSelected = selectedExercise == .squat
        pushUpCard.isSelected = selectedExercise == .pushUp
    }
}
