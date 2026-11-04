import UIKit

final class SettingsViewController: RDBaseViewController {
    private enum Row: Int, CaseIterable {
        case sound
        case haptics
        case countdown
        case mirror
        case intensity
        case healthData
        case privacy
        case clearHistory
    }

    private let preferences: AppPreferences
    private let store: WorkoutPersistenceStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(preferences: AppPreferences, store: WorkoutPersistenceStore) {
        self.preferences = preferences
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings".rdLocalized
        navigationItem.largeTitleDisplayMode = .always
        tableView.backgroundColor = RDColor.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Setting")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Stepper")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
    }

    private func makeSwitch(isOn: Bool, action: @escaping (Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = isOn
        control.onTintColor = RDColor.accent
        control.addAction(UIAction { action(($0.sender as? UISwitch)?.isOn ?? false) }, for: .valueChanged)
        return control
    }

    private func showPrivacy() {
        let alert = UIAlertController(
            title: "Private by design".rdLocalized,
            message: "Camera frames and pose masks are processed on this iPhone. RepDuo does not save or upload video. Workout history contains summary statistics only.".rdLocalized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Done".rdLocalized, style: .default))
        present(alert, animated: true)
    }

    private func confirmClearHistory() {
        let alert = UIAlertController(
            title: "Clear workout history?".rdLocalized,
            message: "This removes saved workout summaries from this iPhone. It cannot be undone.".rdLocalized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel".rdLocalized, style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear".rdLocalized, style: .destructive) { [weak self] _ in
            do { try self?.store.deleteAll() }
            catch { self?.showStoreError(error) }
        })
        present(alert, animated: true)
    }

    private func showStoreError(_ error: Error) {
        let alert = UIAlertController(title: "Could not clear history".rdLocalized, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK".rdLocalized, style: .default))
        present(alert, animated: true)
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 6
        case 1: return 1
        default: return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "TRAINING".rdLocalized
        case 1: return "NEON BODY".rdLocalized
        default: return "DATA & PRIVACY".rdLocalized
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0, indexPath.row < 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Stepper", for: indexPath)
            cell.backgroundColor = RDColor.card
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                configureStepper(
                    cell,
                    title: "Daily goal",
                    value: preferences.dailyRepGoal,
                    range: AppPreferences.dailyRepGoalRange,
                    step: 10
                ) { [weak self] in self?.preferences.dailyRepGoal = $0 }
            } else {
                configureStepper(
                    cell,
                    title: "Reps per set",
                    value: preferences.setRepTarget,
                    range: AppPreferences.setRepTargetRange,
                    step: 5
                ) { [weak self] in self?.preferences.setRepTarget = $0 }
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "Setting", for: indexPath)
        cell.backgroundColor = RDColor.card
        cell.textLabel?.textColor = RDColor.label
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.imageView?.image = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            switch indexPath.row {
            case 2:
                cell.textLabel?.text = "Audio cues".rdLocalized
                cell.accessoryView = makeSwitch(isOn: preferences.soundEnabled) { [weak self] in self?.preferences.soundEnabled = $0 }
            case 3:
                cell.textLabel?.text = "Haptic feedback".rdLocalized
                cell.accessoryView = makeSwitch(isOn: preferences.hapticsEnabled) { [weak self] in self?.preferences.hapticsEnabled = $0 }
            case 4:
                cell.textLabel?.text = "Three-second countdown".rdLocalized
                cell.accessoryView = makeSwitch(isOn: preferences.countdownEnabled) { [weak self] in self?.preferences.countdownEnabled = $0 }
            default:
                cell.textLabel?.text = "Mirror front camera".rdLocalized
                cell.accessoryView = makeSwitch(isOn: preferences.mirrorFrontCamera) { [weak self] in self?.preferences.mirrorFrontCamera = $0 }
            }
        } else if indexPath.section == 1 {
            cell.textLabel?.text = "Glow intensity".rdLocalized
            let slider = UISlider()
            slider.minimumValue = 0.35
            slider.maximumValue = 1
            slider.value = preferences.neonIntensity
            slider.minimumTrackTintColor = RDColor.accent
            slider.widthAnchor.constraint(equalToConstant: 145).isActive = true
            slider.addAction(UIAction { [weak self] action in
                self?.preferences.neonIntensity = (action.sender as? UISlider)?.value ?? 0.85
            }, for: .valueChanged)
            cell.accessoryView = slider
        } else if indexPath.row == 0 {
            cell.textLabel?.text = "Health data · Not requested".rdLocalized
            cell.textLabel?.textColor = RDColor.secondaryLabel
            cell.accessibilityLabel = "Health data permission, not requested in this version".rdLocalized
        } else if indexPath.row == 1 {
            cell.textLabel?.text = "Privacy details".rdLocalized
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else {
            cell.textLabel?.text = "Clear workout history".rdLocalized
            cell.textLabel?.textColor = RDColor.destructive
            cell.selectionStyle = .default
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2, indexPath.row > 0 {
            if indexPath.row == 1 { showPrivacy() } else { confirmClearHistory() }
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}

private extension SettingsViewController {
    /// Title and current value on the left, a system stepper on the right.
    func configureStepper(
        _ cell: UITableViewCell,
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        step: Int,
        onChange: @escaping (Int) -> Void
    ) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = title.rdLocalized
        content.secondaryText = "%d reps".rdLocalizedFormat(value)
        content.secondaryTextProperties.color = RDColor.secondaryLabel
        cell.contentConfiguration = content
        let stepper = UIStepper()
        stepper.minimumValue = Double(range.lowerBound)
        stepper.maximumValue = Double(range.upperBound)
        stepper.stepValue = Double(step)
        stepper.value = Double(value)
        stepper.accessibilityLabel = title.rdLocalized
        let selection = UISelectionFeedbackGenerator()
        stepper.addAction(UIAction { [weak self, weak cell] action in
            guard let stepper = action.sender as? UIStepper else { return }
            let next = Int(stepper.value)
            onChange(next)
            if self?.preferences.hapticsEnabled == true { selection.selectionChanged() }
            guard var content = cell?.contentConfiguration as? UIListContentConfiguration else { return }
            content.secondaryText = "%d reps".rdLocalizedFormat(next)
            cell?.contentConfiguration = content
        }, for: .valueChanged)
        cell.accessoryView = stepper
    }
}
