import os
import UIKit

final class AppCoordinator {
    private let navigationController: UINavigationController
    private let container: DependencyContainer
    private let logger = Logger(subsystem: "com.repduo.ios", category: "app.lifecycle")

    init(navigationController: UINavigationController, container: DependencyContainer) {
        self.navigationController = navigationController
        self.container = container
        configureNavigationBar()
    }

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-previewWorkout") {
            showWorkout(for: .pushUp)
            return
        }
        #endif
        if container.preferences.hasCompletedOnboarding {
            showChoose(animated: false)
        } else {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        let controller = OnboardingViewController()
        controller.onContinue = { [weak self] in self?.showCameraPermission() }
        navigationController.setViewControllers([controller], animated: false)
    }

    private func showCameraPermission() {
        let controller = CameraPermissionViewController(mode: .rationale, service: container.cameraAuthorization)
        controller.onContinue = { [weak self] in self?.showGearCheck() }
        controller.onDenied = { [weak self] in self?.showOnboardingCameraDenied() }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showOnboardingCameraDenied() {
        let controller = CameraPermissionViewController(mode: .denied, service: container.cameraAuthorization)
        controller.onContinue = { [weak self] in self?.showGearCheck() }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showGearCheck() {
        let controller = GearCheckViewController(
            watchService: container.watchStatus,
            audioService: container.audioRoute,
            preferences: container.preferences
        )
        controller.onContinue = { [weak self] in
            guard let self else { return }
            self.container.preferences.hasCompletedOnboarding = true
            self.showChoose(animated: true)
        }
        navigationController.pushViewController(controller, animated: true)
    }

    private func showChoose(animated: Bool) {
        container.cameraPipeline.stop()
        let controller = ChooseViewController(preferences: container.preferences, feedback: container.feedback)
        controller.onStart = { [weak self] exercise in self?.showCameraSetup(for: exercise) }
        controller.onHistory = { [weak self] in self?.showHistory() }
        controller.onSettings = { [weak self] in self?.showSettings() }
        navigationController.setViewControllers([controller], animated: animated)
    }

    private func showCameraSetup(for exercise: ExerciseType) {
        guard container.cameraAuthorization.state != .denied else {
            let denied = CameraPermissionViewController(mode: .denied, service: container.cameraAuthorization)
            denied.onContinue = { [weak self, weak denied] in
                guard let self else { return }
                if let denied, self.navigationController.topViewController === denied {
                    self.navigationController.popViewController(animated: false)
                }
                self.showCameraSetup(for: exercise)
            }
            navigationController.pushViewController(denied, animated: true)
            return
        }
        let controller = CameraSetupViewController(
            exercise: exercise,
            pipeline: container.cameraPipeline,
            preferences: container.preferences,
            cameraAccess: container.cameraAuthorization
        )
        controller.onContinue = { [weak self] in self?.beginCountdownOrWorkout(for: exercise) }
        navigationController.pushViewController(controller, animated: true)
    }

    private func beginCountdownOrWorkout(for exercise: ExerciseType) {
        if container.preferences.countdownEnabled {
            let controller = CountdownViewController(
                exercise: exercise,
                pipeline: container.cameraPipeline,
                cameraAccess: container.cameraAuthorization,
                feedback: container.feedback
            )
            controller.onComplete = { [weak self] in self?.showWorkout(for: exercise) }
            navigationController.pushViewController(controller, animated: true)
        } else {
            showWorkout(for: exercise)
        }
    }

    private func showWorkout(for exercise: ExerciseType) {
        let trackingMode = container.preferences.bodyTrackingMode
        let session = WorkoutSession(
            exercise: exercise,
            trackingMode: trackingMode,
            baseline: container.preferences.movementBaseline(
                for: exercise,
                trackingMode: trackingMode
            )
        )
        let controller = WorkoutViewController(
            session: session,
            pipeline: container.cameraPipeline,
            cameraAccess: container.cameraAuthorization,
            feedback: container.feedback,
            preferences: container.preferences,
            audioService: container.audioRoute
        )
        controller.onFinish = { [weak self] summary in self?.complete(summary) }
        navigationController.pushViewController(controller, animated: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-previewCoachScore") {
            session.registerDebugRep()
            session.registerDebugRep()
            session.registerDebugRep()
        }
        #endif
    }

    private func complete(_ summary: WorkoutSummary) {
        if let learnedBaseline = summary.learnedBaseline {
            container.preferences.saveMovementBaseline(
                learnedBaseline,
                for: summary.exercise,
                trackingMode: container.preferences.bodyTrackingMode
            )
        }
        do {
            try container.persistence.save(summary)
        } catch {
            logger.error("Workout summary save failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
        }
        let controller = CompleteViewController(summary: summary)
        controller.onDone = { [weak self] in self?.showChoose(animated: true) }
        controller.onAnotherSet = { [weak self] in
            guard let self else { return }
            self.showChoose(animated: false)
            self.showCameraSetup(for: summary.exercise)
        }
        navigationController.setViewControllers([controller], animated: true)
    }

    private func showHistory() {
        navigationController.pushViewController(HistoryViewController(store: container.persistence), animated: true)
    }

    private func showSettings() {
        let controller = SettingsViewController(preferences: container.preferences, store: container.persistence)
        navigationController.pushViewController(controller, animated: true)
    }

    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = RDColor.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: RDColor.warmWhite,
            .font: UIFont.systemFont(ofSize: 14, weight: .bold)
        ]
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        navigationController.navigationBar.tintColor = RDColor.warmWhite
    }
}
