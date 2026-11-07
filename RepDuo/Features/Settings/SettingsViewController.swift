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
    private let ghosts: GhostStore
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(preferences: AppPreferences, store: WorkoutPersistenceStore, ghosts: GhostStore) {
        self.preferences = preferences
        self.store = store
        self.ghosts = ghosts
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SETTINGS".rdLocalized
        tableView.backgroundColor = RDColor.background
        tableView.separatorColor = RDColor.surfaceSecondary
        tableView.sectionHeaderTopPadding = 18
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Setting")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
    }

    private func makeSwitch(isOn: Bool, action: @escaping (Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = isOn
        control.onTintColor = RDColor.neonGreen
        control.thumbTintColor = nil
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
            // Ghosts are past sets too, so they go with the history.
            self?.ghosts.deleteAll()
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "Setting", for: indexPath)
        cell.backgroundColor = RDColor.surface
        cell.textLabel?.textColor = RDColor.warmWhite
        cell.textLabel?.font = RDFont.body(weight: .semibold)
        cell.imageView?.image = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Daily goal".rdLocalized
                cell.accessoryView = RDStepperView(
                    value: preferences.dailyRepGoal,
                    range: AppPreferences.dailyRepGoalRange,
                    step: 10,
                    label: "Daily goal"
                ) { [weak self] in self?.preferences.dailyRepGoal = $0 }
            case 1:
                cell.textLabel?.text = "Reps per set".rdLocalized
                cell.accessoryView = RDStepperView(
                    value: preferences.setRepTarget,
                    range: AppPreferences.setRepTargetRange,
                    step: 5,
                    label: "Reps per set"
                ) { [weak self] in self?.preferences.setRepTarget = $0 }
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
            slider.minimumTrackTintColor = RDColor.neonGreen
            slider.widthAnchor.constraint(equalToConstant: 145).isActive = true
            slider.addAction(UIAction { [weak self] action in
                self?.preferences.neonIntensity = (action.sender as? UISlider)?.value ?? 0.85
            }, for: .valueChanged)
            cell.accessoryView = slider
        } else if indexPath.row == 0 {
            cell.textLabel?.text = "Health data · Not requested".rdLocalized
            cell.textLabel?.textColor = RDColor.textSecondary
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

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = RDColor.neonGreen
        header.textLabel?.font = RDFont.eyebrow(13)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}

/// Compact −/value/+ control that reads as an adjustable element in VoiceOver.
private final class RDStepperView: UIView {
    private let valueLabel = UILabel()
    private let range: ClosedRange<Int>
    private let step: Int
    private let onChange: (Int) -> Void
    private var value: Int

    init(value: Int, range: ClosedRange<Int>, step: Int, label: String, onChange: @escaping (Int) -> Void) {
        self.value = value
        self.range = range
        self.step = step
        self.onChange = onChange
        super.init(frame: CGRect(x: 0, y: 0, width: 128, height: 40))
        valueLabel.font = RDFont.numeric(24, maximumScale: 1)
        valueLabel.textColor = RDColor.warmWhite
        valueLabel.textAlignment = .center
        let minus = makeButton("minus") { [weak self] in self?.adjust(by: -1) }
        let plus = makeButton("plus") { [weak self] in self?.adjust(by: 1) }
        let stack = UIStackView(axis: .horizontal, spacing: 4, arrangedSubviews: [minus, valueLabel, plus])
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = bounds
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stack)
        isAccessibilityElement = true
        accessibilityLabel = label.rdLocalized
        accessibilityTraits = .adjustable
        render()
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityIncrement() { adjust(by: 1) }
    override func accessibilityDecrement() { adjust(by: -1) }

    private func makeButton(_ symbol: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy))
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = RDColor.surfaceSecondary
        configuration.baseForegroundColor = RDColor.warmWhite
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func adjust(by direction: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + direction * step))
        guard next != value else { return }
        value = next
        render()
        onChange(next)
    }

    private func render() {
        valueLabel.text = String(value)
        accessibilityValue = String(value)
    }
}
