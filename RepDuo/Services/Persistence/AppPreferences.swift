import Foundation
#if canImport(RepDuoCore)
import RepDuoCore
#endif

final class AppPreferences {
    private enum Key {
        static let completedOnboarding = "completedOnboarding"
        static let soundEnabled = "soundEnabled"
        static let hapticsEnabled = "hapticsEnabled"
        static let countdownEnabled = "countdownEnabled"
        static let mirrorFrontCamera = "mirrorFrontCamera"
        static let cameraFramingMode = "cameraFramingMode"
        static let bodyTrackingMode = "bodyTrackingMode"
        static let neonIntensity = "neonIntensity"
        static let lastExercise = "lastExercise"
        static let movementBaselinePrefix = "movementBaseline"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            defaults.removeObject(forKey: Key.completedOnboarding)
        }
        defaults.register(defaults: [
            Key.soundEnabled: true,
            Key.hapticsEnabled: true,
            Key.countdownEnabled: true,
            Key.mirrorFrontCamera: true,
            Key.cameraFramingMode: true,
            Key.bodyTrackingMode: BodyTrackingMode.fullBody.rawValue,
            Key.neonIntensity: 0.85
        ])
        if arguments.contains("-disableCountdown") { defaults.set(false, forKey: Key.countdownEnabled) }
        if arguments.contains("-uiTesting") {
            defaults.set(false, forKey: Key.soundEnabled)
            defaults.set(false, forKey: Key.hapticsEnabled)
            defaults.set(true, forKey: Key.cameraFramingMode)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.completedOnboarding) }
        set { defaults.set(newValue, forKey: Key.completedOnboarding) }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEnabled) }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    var hapticsEnabled: Bool {
        get { defaults.bool(forKey: Key.hapticsEnabled) }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }

    var countdownEnabled: Bool {
        get { defaults.bool(forKey: Key.countdownEnabled) }
        set { defaults.set(newValue, forKey: Key.countdownEnabled) }
    }

    var mirrorFrontCamera: Bool {
        get { defaults.bool(forKey: Key.mirrorFrontCamera) }
        set { defaults.set(newValue, forKey: Key.mirrorFrontCamera) }
    }

    var prefersWideCamera: Bool {
        get { defaults.bool(forKey: Key.cameraFramingMode) }
        set { defaults.set(newValue, forKey: Key.cameraFramingMode) }
    }

    var bodyTrackingMode: BodyTrackingMode {
        get { BodyTrackingMode(rawValue: defaults.string(forKey: Key.bodyTrackingMode) ?? "") ?? .fullBody }
        set { defaults.set(newValue.rawValue, forKey: Key.bodyTrackingMode) }
    }

    var neonIntensity: Float {
        get { defaults.float(forKey: Key.neonIntensity) }
        set { defaults.set(newValue, forKey: Key.neonIntensity) }
    }

    var lastExercise: ExerciseType {
        get { ExerciseType(rawValue: defaults.string(forKey: Key.lastExercise) ?? "") ?? .squat }
        set { defaults.set(newValue.rawValue, forKey: Key.lastExercise) }
    }

    func movementBaseline(
        for exercise: ExerciseType,
        trackingMode: BodyTrackingMode
    ) -> MovementBaseline? {
        guard let data = defaults.data(forKey: baselineKey(exercise, trackingMode)) else { return nil }
        return try? JSONDecoder().decode(MovementBaseline.self, from: data)
    }

    func saveMovementBaseline(
        _ baseline: MovementBaseline,
        for exercise: ExerciseType,
        trackingMode: BodyTrackingMode
    ) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        defaults.set(data, forKey: baselineKey(exercise, trackingMode))
    }

    private func baselineKey(_ exercise: ExerciseType, _ trackingMode: BodyTrackingMode) -> String {
        "\(Key.movementBaselinePrefix).\(exercise.rawValue).\(trackingMode.rawValue)"
    }
}
