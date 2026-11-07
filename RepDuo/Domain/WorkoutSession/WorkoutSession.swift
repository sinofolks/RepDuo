import Foundation

struct WorkoutViewState: Equatable, Sendable {
    let exercise: ExerciseType
    let phase: ExercisePhase
    let repCount: Int
    let poseQuality: PoseQuality
    let coachingMessage: String?
    let lastRepCoaching: RepCoachingResult?
    let heartRate: Int?
    let isPaused: Bool
    let rendererQuality: RendererQuality
    /// Reward for the most recent rep; stays set until the next rep replaces it.
    let reward: RepReward?
    /// 0...1 toward five stars.
    let starProgress: Double

    var stars: Int { RepRewardTracker.stars(for: starProgress) }
}

final class WorkoutSession {
    private let detector: RepDetectionEngine
    private let coach: MovementCoach
    private let startedAt: Date
    private let monotonicStart: TimeInterval
    private var pauseStartedAt: TimeInterval?
    private var totalPausedDuration: TimeInterval = 0
    private var lastQuality: PoseQuality = .unstable
    private var lowConfidenceEventCount = 0
    private var heartRates: [Double] = []
    private var assessmentMessageUntil: TimeInterval?
    private var rewardTracker: RepRewardTracker
    private var ghostRecorder = GhostRecorder()

    let exercise: ExerciseType
    /// Best earlier set of this move, raced live; nil until one is recorded.
    let ghost: GhostTrack?
    private(set) var state: WorkoutViewState

    var onStateChange: ((WorkoutViewState, Bool) -> Void)?

    init(
        exercise: ExerciseType,
        trackingMode: BodyTrackingMode = .fullBody,
        baseline: MovementBaseline? = nil,
        setTarget: Int = 12,
        personalBest: Int = 0,
        ghost: GhostTrack? = nil,
        startedAt: Date = Date(),
        monotonicStart: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.exercise = exercise
        self.ghost = ghost?.exercise == exercise ? ghost : nil
        self.startedAt = startedAt
        self.monotonicStart = monotonicStart
        self.detector = RepDetectionEngine(exercise: exercise)
        self.rewardTracker = RepRewardTracker(target: setTarget, personalBest: personalBest)
        self.coach = MovementCoach(
            exercise: exercise,
            trackingMode: trackingMode,
            baseline: baseline
        )
        self.state = WorkoutViewState(
            exercise: exercise,
            phase: .ready,
            repCount: 0,
            poseQuality: .unstable,
            coachingMessage: baseline?.isPersonalized == true
                ? "AI Coach is personalized and ready.".rdLocalized
                : "AI Coach will learn from your first three clear reps.".rdLocalized,
            lastRepCoaching: nil,
            heartRate: nil,
            isPaused: false,
            rendererQuality: .balanced,
            reward: nil,
            starProgress: 0
        )
    }

    func process(_ frame: PoseFrame) {
        guard !state.isPaused else { return }
        if !frame.quality.permitsCounting && lastQuality.permitsCounting {
            lowConfidenceEventCount += 1
        }
        lastQuality = frame.quality
        let update = detector.process(frame)
        let assessment = coach.process(
            frame: frame,
            phase: update.phase,
            completedRep: update.completedRep,
            repNumber: update.repCount
        )
        if assessment != nil {
            assessmentMessageUntil = frame.timestamp + 2.4
        }
        let elapsed = activeElapsed(at: frame.timestamp)
        if frame.quality.permitsCounting {
            ghostRecorder.record(frame.joints, at: elapsed)
        }
        if update.completedRep {
            rewardTracker.register(repNumber: update.repCount, score: assessment?.score)
            ghostRecorder.markRep(at: elapsed)
        }
        let latestAssessment = assessment ?? state.lastRepCoaching
        let message: String
        if !frame.quality.permitsCounting {
            message = frame.quality.message
        } else if let latestAssessment,
                  let assessmentMessageUntil,
                  frame.timestamp <= assessmentMessageUntil {
            message = latestAssessment.statusText
        } else {
            message = coachingMessage(for: frame.quality, phase: update.phase)
        }
        state = WorkoutViewState(
            exercise: exercise,
            phase: update.phase,
            repCount: update.repCount,
            poseQuality: frame.quality,
            coachingMessage: message,
            lastRepCoaching: latestAssessment,
            heartRate: state.heartRate,
            isPaused: false,
            rendererQuality: state.rendererQuality,
            reward: rewardTracker.lastReward,
            starProgress: rewardTracker.progress
        )
        onStateChange?(state, update.completedRep)
    }

    func pause(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !state.isPaused else { return }
        pauseStartedAt = timestamp
        state = replacingState(isPaused: true, message: "Workout paused.".rdLocalized)
        onStateChange?(state, false)
    }

    func resume(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard state.isPaused else { return }
        if let pauseStartedAt { totalPausedDuration += max(0, timestamp - pauseStartedAt) }
        self.pauseStartedAt = nil
        state = replacingState(isPaused: false, message: state.poseQuality.message)
        onStateChange?(state, false)
    }

    func updateHeartRate(_ beatsPerMinute: Double) {
        guard beatsPerMinute > 0 else { return }
        heartRates.append(beatsPerMinute)
        state = WorkoutViewState(
            exercise: state.exercise,
            phase: state.phase,
            repCount: state.repCount,
            poseQuality: state.poseQuality,
            coachingMessage: state.coachingMessage,
            lastRepCoaching: state.lastRepCoaching,
            heartRate: Int(beatsPerMinute.rounded()),
            isPaused: state.isPaused,
            rendererQuality: state.rendererQuality,
            reward: rewardTracker.lastReward,
            starProgress: rewardTracker.progress
        )
        onStateChange?(state, false)
    }

    func setRendererQuality(_ quality: RendererQuality) {
        state = WorkoutViewState(
            exercise: state.exercise,
            phase: state.phase,
            repCount: state.repCount,
            poseQuality: state.poseQuality,
            coachingMessage: state.coachingMessage,
            lastRepCoaching: state.lastRepCoaching,
            heartRate: state.heartRate,
            isPaused: state.isPaused,
            rendererQuality: quality,
            reward: rewardTracker.lastReward,
            starProgress: rewardTracker.progress
        )
        onStateChange?(state, false)
    }

    func registerDebugRep(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !state.isPaused else { return }
        let update = detector.registerDebugRep()
        let assessment = coach.registerDebugRep(repNumber: update.repCount, timestamp: timestamp)
        assessmentMessageUntil = timestamp + 2.4
        rewardTracker.register(repNumber: update.repCount, score: assessment.score)
        ghostRecorder.markRep(at: activeElapsed(at: timestamp))
        state = WorkoutViewState(
            exercise: state.exercise,
            phase: update.phase,
            repCount: update.repCount,
            poseQuality: .excellent,
            coachingMessage: assessment.statusText,
            lastRepCoaching: assessment,
            heartRate: state.heartRate,
            isPaused: false,
            rendererQuality: state.rendererQuality,
            reward: rewardTracker.lastReward,
            starProgress: rewardTracker.progress
        )
        onStateChange?(state, true)
    }

    /// Seconds of unpaused set time at `timestamp`; the ghost's clock.
    func activeElapsed(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        var paused = totalPausedDuration
        if let pauseStartedAt { paused += max(0, timestamp - pauseStartedAt) }
        return max(0, timestamp - monotonicStart - paused)
    }

    /// Live standing against the ghost, or nil when there is none to race.
    func ghostStatus(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GhostRaceStatus? {
        ghost.map { GhostRaceStatus(track: $0, liveReps: state.repCount, elapsed: activeElapsed(at: timestamp)) }
    }

    func finish(at date: Date = Date(), monotonicTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> WorkoutSummary {
        let duration = activeElapsed(at: monotonicTime)
        return WorkoutSummary(
            exercise: exercise,
            startedAt: startedAt,
            endedAt: date,
            repCount: state.repCount,
            activeDuration: duration,
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
            maximumHeartRate: heartRates.max(),
            lowConfidenceEventCount: lowConfidenceEventCount,
            coachingReport: coach.report(),
            learnedBaseline: coach.baseline,
            rewards: rewardTracker.summary,
            ghostTrack: ghostRecorder.track(exercise: exercise, duration: duration, recordedAt: startedAt)
        )
    }

    private func replacingState(isPaused: Bool, message: String?) -> WorkoutViewState {
        WorkoutViewState(
            exercise: state.exercise,
            phase: state.phase,
            repCount: state.repCount,
            poseQuality: state.poseQuality,
            coachingMessage: message,
            lastRepCoaching: state.lastRepCoaching,
            heartRate: state.heartRate,
            isPaused: isPaused,
            rendererQuality: state.rendererQuality,
            reward: rewardTracker.lastReward,
            starProgress: rewardTracker.progress
        )
    }

    private func coachingMessage(for quality: PoseQuality, phase: ExercisePhase) -> String {
        guard quality.permitsCounting else { return quality.message }
        switch phase {
        case .ready: return "Ready. Control the movement.".rdLocalized
        case .down: return "Down. Stay controlled.".rdLocalized
        case .hold: return "Good depth. Drive back up.".rdLocalized
        case .up: return "Up. Finish tall.".rdLocalized
        }
    }
}
