import UIKit

final class HistoryViewController: RDBaseViewController {
    private let store: WorkoutPersistenceStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let filter = UISegmentedControl(items: ["ALL".rdLocalized, "SQUAT".rdLocalized, "PUSH-UP".rdLocalized])
    private var records: [WorkoutSummary] = []

    init(store: WorkoutPersistenceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "HISTORY".rdLocalized
        filter.selectedSegmentIndex = 0
        filter.selectedSegmentTintColor = RDColor.neonGreen
        filter.setTitleTextAttributes([.foregroundColor: RDColor.background, .font: UIFont.systemFont(ofSize: 11, weight: .bold)], for: .selected)
        filter.setTitleTextAttributes([.foregroundColor: RDColor.textSecondary, .font: UIFont.systemFont(ofSize: 11, weight: .bold)], for: .normal)
        filter.addAction(UIAction { [weak self] _ in self?.tableView.reloadData() }, for: .valueChanged)
        filter.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = RDColor.background
        tableView.separatorColor = RDColor.separatorOnDark
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Record")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filter)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            filter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: RDSpacing.lg),
            filter.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -RDSpacing.lg),
            filter.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: RDSpacing.md),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: RDSpacing.sm),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        loadRecords()
    }

    private var filteredRecords: [WorkoutSummary] {
        switch filter.selectedSegmentIndex {
        case 1: return records.filter { $0.exercise == .squat }
        case 2: return records.filter { $0.exercise == .pushUp }
        default: return records
        }
    }

    private func loadRecords() {
        do {
            records = try store.fetchAll()
            tableView.reloadData()
        } catch {
            let alert = UIAlertController(title: "History unavailable".rdLocalized, message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK".rdLocalized, style: .default))
            present(alert, animated: true)
        }
    }
}

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = filteredRecords.count
        if count == 0 {
            let label = UILabel()
            label.text = "NO SETS YET\n\nFinish a squat or push-up set to see it here.".rdLocalized
            label.textColor = RDColor.textSecondary
            label.font = RDFont.body(weight: .semibold)
            label.numberOfLines = 0
            label.textAlignment = .center
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
        return count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = filteredRecords[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Record", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "%1$@ · %2$d REPS".rdLocalizedFormat(record.exercise.displayName, record.repCount)
        content.secondaryText = record.startedAt.formatted(date: .abbreviated, time: .shortened)
        content.image = UIImage(systemName: record.exercise.symbolName)
        content.imageProperties.tintColor = RDColor.neonGreen
        content.textProperties.color = RDColor.warmWhite
        content.textProperties.font = .systemFont(ofSize: 16, weight: .bold)
        content.secondaryTextProperties.color = RDColor.textSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = RDColor.surface
        cell.selectionStyle = .none
        cell.accessibilityLabel = "%1$@, %2$d reps, %3$@".rdLocalizedFormat(
            record.exercise.displayName,
            record.repCount,
            record.startedAt.formatted()
        )
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 76 }
}
