import UIKit

final class HistoryViewController: RDBaseViewController {
    private enum Filter: Int, CaseIterable {
        case all, squat, pushUp

        var title: String {
            switch self {
            case .all: return "ALL".rdLocalized
            case .squat: return ExerciseType.squat.displayName
            case .pushUp: return ExerciseType.pushUp.displayName
            }
        }
    }

    private let store: WorkoutPersistenceStore
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerContainer = UIView()
    private let squatBest = RDStatTile(caption: "", valueColor: RDColor.neonGreen, valueSize: 44)
    private let pushUpBest = RDStatTile(caption: "", valueSize: 44)
    private let heatmap = RDHeatmapView()
    private let streakLabel = UILabel()
    private var filterButtons: [UIButton] = []
    private var filter: Filter = .all
    private var records: [WorkoutSummary] = []
    private var stats = WorkoutStats(summaries: [])

    init(store: WorkoutPersistenceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = nil
        tableView.backgroundColor = RDColor.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(HistoryRecordCell.self, forCellReuseIdentifier: HistoryRecordCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
        tableView.tableHeaderView = makeHeader()
        loadRecords()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if header.frame.size != size {
            header.frame.size = size
            tableView.tableHeaderView = header
        }
    }

    private func makeHeader() -> UIView {
        let title = makeLabel(text: "HISTORY", font: RDFont.display(34))
        title.accessibilityTraits = .header

        let bests = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [squatBest, pushUpBest])
        bests.distribution = .fillEqually

        let calendarCard = makeCard()
        let calendarTitle = makeLabel(text: "Last 4 weeks", font: RDFont.body(weight: .black))
        streakLabel.font = .systemFont(ofSize: 13, weight: .bold)
        streakLabel.textColor = RDColor.ember
        let calendarHeader = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: [calendarTitle, UIView(), streakLabel])
        calendarHeader.alignment = .center
        let legend = UIStackView(axis: .horizontal, spacing: 6)
        legend.addArrangedSubview(UIView())
        legend.addArrangedSubview(makeLabel(text: "Less", font: .systemFont(ofSize: 11), color: RDColor.textMuted))
        for shade in RDHeatmapView.shades {
            let swatch = UIView()
            swatch.backgroundColor = shade
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.widthAnchor.constraint(equalToConstant: 10).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 10).isActive = true
            legend.addArrangedSubview(swatch)
        }
        legend.addArrangedSubview(makeLabel(text: "More", font: .systemFont(ofSize: 11), color: RDColor.textMuted))
        legend.alignment = .center
        legend.isAccessibilityElement = false
        let calendarStack = UIStackView(axis: .vertical, spacing: 12, arrangedSubviews: [calendarHeader, heatmap, legend])
        calendarStack.setCustomSpacing(8, after: heatmap)
        calendarCard.addSubview(calendarStack)
        calendarStack.pinEdges(to: calendarCard, insets: NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))

        let filters = UIStackView(axis: .horizontal, spacing: 8, arrangedSubviews: Filter.allCases.map(makeFilterButton))
        let filterRow = UIStackView(axis: .horizontal, spacing: 0, arrangedSubviews: [filters, UIView()])

        let stack = UIStackView(axis: .vertical, spacing: 8, arrangedSubviews: [title, bests, calendarCard, filterRow])
        stack.setCustomSpacing(16, after: title)
        stack.setCustomSpacing(18, after: calendarCard)
        headerContainer.addSubview(stack)
        stack.pinEdges(to: headerContainer, insets: NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        renderFilters()
        return headerContainer
    }

    private func makeFilterButton(_ filter: Filter) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = filter.title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 13, weight: .black)
            return outgoing
        }
        button.configuration = configuration
        button.tag = filter.rawValue
        button.accessibilityIdentifier = "history.filter.\(filter.rawValue)"
        button.addAction(UIAction { [weak self] _ in
            self?.filter = filter
            self?.renderFilters()
            self?.reloadRows()
        }, for: .touchUpInside)
        filterButtons.append(button)
        return button
    }

    private func renderFilters() {
        for button in filterButtons {
            let isSelected = button.tag == filter.rawValue
            button.configuration?.baseBackgroundColor = isSelected ? RDColor.warmWhite : RDColor.surface
            button.configuration?.baseForegroundColor = isSelected ? RDColor.background : RDColor.textBody
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    /// Reloads rows and shows the empty message under the header when the filter has no sets.
    private func reloadRows() {
        tableView.reloadData()
        guard filteredRecords.isEmpty else {
            tableView.tableFooterView = UIView()
            return
        }
        let label = UILabel()
        label.text = "NO SETS YET\n\nFinish a squat or push-up set to see it here.".rdLocalized
        label.textColor = RDColor.textSecondary
        label.font = RDFont.body(weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .center
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 180))
        footer.addSubview(label)
        label.pinEdges(to: footer, insets: NSDirectionalEdgeInsets(top: 24, leading: 32, bottom: 24, trailing: 32))
        tableView.tableFooterView = footer
    }

    private var filteredRecords: [WorkoutSummary] {
        switch filter {
        case .squat: return records.filter { $0.exercise == .squat }
        case .pushUp: return records.filter { $0.exercise == .pushUp }
        case .all: return records
        }
    }

    private func loadRecords() {
        do {
            records = try store.fetchAll()
        } catch {
            let alert = UIAlertController(title: "History unavailable".rdLocalized, message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK".rdLocalized, style: .default))
            present(alert, animated: true)
        }
        stats = WorkoutStats(summaries: records)
        renderBest(squatBest, exercise: .squat)
        renderBest(pushUpBest, exercise: .pushUp)
        heatmap.render(dailyReps: stats.recentDailyReps)
        streakLabel.text = stats.streakDays > 0 ? "%d-day streak".rdLocalizedFormat(stats.streakDays) : nil
        reloadRows()
    }

    private func renderBest(_ tile: RDStatTile, exercise: ExerciseType) {
        let best = stats.personalBest(for: exercise)
        let date = records.first { $0.exercise == exercise && $0.repCount == best && best > 0 }?
            .startedAt.formatted(.dateTime.month(.defaultDigits).day())
        let caption = [
            "%@ best set".rdLocalizedFormat(exercise.displayName),
            date
        ].compactMap { $0 }.joined(separator: " · ")
        tile.update(value: best > 0 ? String(best) : "—", caption: caption)
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = filteredRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryRecordCell.reuseIdentifier, for: indexPath)
        (cell as? HistoryRecordCell)?.render(record, isBest: record.repCount > 0 && record.repCount == stats.personalBest(for: record.exercise))
        return cell
    }
}

private final class HistoryRecordCell: UITableViewCell {
    static let reuseIdentifier = "Record"
    private let repsLabel = UILabel()
    private let moveLabel = UILabel()
    private let metaLabel = UILabel()
    private let badge = RDTag(text: "PB", background: RDColor.ember)
    private let tempoLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = RDColor.background
        selectionStyle = .none
        repsLabel.font = RDFont.numeric(36)
        repsLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
        moveLabel.font = RDFont.body(weight: .bold)
        moveLabel.textColor = RDColor.warmWhite
        moveLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = RDFont.caption(weight: .regular)
        metaLabel.textColor = RDColor.textSecondary
        metaLabel.numberOfLines = 0
        metaLabel.adjustsFontForContentSizeCategory = true
        tempoLabel.font = RDFont.numeric(14, weight: .heavy, italic: false)
        tempoLabel.textColor = RDColor.textSecondary
        badge.setContentHuggingPriority(.required, for: .horizontal)
        tempoLabel.setContentHuggingPriority(.required, for: .horizontal)
        let texts = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [moveLabel, metaLabel])
        texts.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let row = UIStackView(axis: .horizontal, spacing: 14, arrangedSubviews: [repsLabel, texts, badge, tempoLabel])
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: NSDirectionalEdgeInsets(top: 13, leading: 20, bottom: 13, trailing: 20))
        let line = UIView()
        line.backgroundColor = RDColor.surfaceSecondary
        line.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    func render(_ record: WorkoutSummary, isBest: Bool) {
        repsLabel.text = String(record.repCount)
        repsLabel.textColor = isBest ? RDColor.neonGreen : RDColor.warmWhite
        moveLabel.text = record.exercise.displayName
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        let duration = formatter.string(from: record.activeDuration) ?? "0:00"
        metaLabel.text = "\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(duration)"
        badge.isHidden = !isBest
        tempoLabel.isHidden = isBest
        tempoLabel.text = record.averageTempo.map { "%.1f SEC/REP".rdLocalizedFormat($0) }
        accessibilityLabel = "%1$@, %2$d reps, %3$@".rdLocalizedFormat(
            record.exercise.displayName,
            record.repCount,
            record.startedAt.formatted()
        )
        accessibilityValue = isBest ? "Personal best".rdLocalized : nil
    }
}
