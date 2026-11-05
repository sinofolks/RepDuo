import AVFoundation
import AudioToolbox
import UIKit

final class FeedbackService {
    private let preferences: AppPreferences
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private var lastCoachingCueAt: TimeInterval = -.infinity
    private var lastTrackingCueAt: TimeInterval = -.infinity
    private var lastFormCueAt: TimeInterval = -.infinity

    init(preferences: AppPreferences) {
        self.preferences = preferences
        impact.prepare()
        notification.prepare()
        heavyImpact.prepare()
    }

    func countdown(_ value: Int) {
        if preferences.soundEnabled {
            let utterance = makeUtterance(value == 0 ? "Go".rdLocalized : String(value))
            utterance.rate = 0.54
            utterance.volume = 0.78
            speechSynthesizer.speak(utterance)
        }
        if preferences.hapticsEnabled { impact.impactOccurred(intensity: value == 0 ? 1 : 0.65) }
    }

    /// Gold reps add a heavy tap right after the usual success haptic.
    func repCompleted(isGold: Bool = false) {
        if preferences.soundEnabled { AudioServicesPlaySystemSound(1104) }
        guard preferences.hapticsEnabled else { return }
        notification.notificationOccurred(.success)
        if isGold {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [heavyImpact] in
                heavyImpact.impactOccurred()
            }
        }
    }

    func coach(phase: ExercisePhase) {
        guard preferences.soundEnabled else { return }
        let word: String
        switch phase {
        case .down: word = "Down".rdLocalized
        case .up: word = "Up".rdLocalized
        case .ready, .hold: return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCoachingCueAt >= 0.65 else { return }
        lastCoachingCueAt = now
        let utterance = makeUtterance(word)
        utterance.rate = 0.58
        utterance.volume = 0.72
        speechSynthesizer.speak(utterance)
    }

    func trackingIssue(_ message: String) {
        guard preferences.soundEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTrackingCueAt >= 6 else { return }
        lastTrackingCueAt = now
        let utterance = makeUtterance(message)
        utterance.rate = 0.56
        utterance.volume = 0.68
        speechSynthesizer.speak(utterance)
    }

    func formIssue(_ issue: MovementIssue) {
        guard preferences.soundEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFormCueAt >= 4 else { return }
        lastFormCueAt = now
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .word)
        }
        let utterance = makeUtterance(issue.liveCue)
        utterance.rate = 0.54
        utterance.volume = 0.78
        speechSynthesizer.speak(utterance)
    }

    func workoutCompleted() {
        if preferences.soundEnabled {
            let utterance = makeUtterance("Set complete".rdLocalized)
            utterance.rate = 0.55
            utterance.volume = 0.78
            speechSynthesizer.speak(utterance)
        }
        if preferences.hapticsEnabled { notification.notificationOccurred(.success) }
    }

    func selectionChanged() {
        if preferences.hapticsEnabled { impact.impactOccurred(intensity: 0.55) }
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if let language = Locale.preferredLanguages.first {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        return utterance
    }
}
