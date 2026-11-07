import Foundation
import os

struct RepDetectionUpdate: Equatable, Sendable {
    let phase: ExercisePhase
    let repCount: Int
    let completedRep: Bool
}

struct RepDetectionConfiguration: Equatable, Sendable {
    let topAngle: Double
    let descentAngle: Double
    let bottomAngle: Double
    let bottomExitAngle: Double
    let minimumRange: Double
    let stableFrameCount: Int
    let minimumRepDuration: TimeInterval
    let cooldown: TimeInterval
    let maximumTrackingGap: TimeInterval

    static let squat = RepDetectionConfiguration(
        topAngle: 160,
        descentAngle: 145,
        bottomAngle: 105,
        bottomExitAngle: 118,
        minimumRange: 48,
        stableFrameCount: 2,
        minimumRepDuration: 0.5,
        cooldown: 0.25,
        maximumTrackingGap: 0.8
    )

    static let pushUp = RepDetectionConfiguration(
        topAngle: 160,
        descentAngle: 142,
        bottomAngle: 100,
        bottomExitAngle: 114,
        minimumRange: 52,
        stableFrameCount: 2,
        minimumRepDuration: 0.5,
        cooldown: 0.25,
        maximumTrackingGap: 0.8
    )

    /// Front knee of a split stance; it bends a little less than a deep squat.
    static let lunge = RepDetectionConfiguration(
        topAngle: 155,
        descentAngle: 142,
        bottomAngle: 112,
        bottomExitAngle: 124,
        minimumRange: 40,
        stableFrameCount: 2,
        minimumRepDuration: 0.5,
        cooldown: 0.25,
        maximumTrackingGap: 0.8
    )

    /// Measured as hip drop, so lying flat reads as the top and the lifted bridge as the bottom.
    static let gluteBridge = RepDetectionConfiguration(
        topAngle: 160,
        descentAngle: 150,
        bottomAngle: 132,
        bottomExitAngle: 140,
        minimumRange: 24,
        stableFrameCount: 2,
        minimumRepDuration: 0.5,
        cooldown: 0.25,
        maximumTrackingGap: 0.8
    )

    /// Shoulder–hip–knee angle: about 130° lying with bent knees, closing as the torso curls up.
    static let sitUp = RepDetectionConfiguration(
        topAngle: 120,
        descentAngle: 110,
        bottomAngle: 75,
        bottomExitAngle: 88,
        minimumRange: 38,
        stableFrameCount: 2,
        minimumRepDuration: 0.6,
        cooldown: 0.25,
        maximumTrackingGap: 0.8
    )

    /// Measured as 180° minus arm raise, so arms at the sides read as the top.
    static let jumpingJack = RepDetectionConfiguration(
        topAngle: 145,
        descentAngle: 125,
        bottomAngle: 65,
        bottomExitAngle: 80,
        minimumRange: 70,
        stableFrameCount: 2,
        minimumRepDuration: 0.35,
        cooldown: 0.15,
        maximumTrackingGap: 0.8
    )

    /// Hip bounce from `JumpRopeMotionEstimator`: 180° on the ground, falling as the body lifts.
    /// Skips are quick and small, so one frame is enough to confirm a stage.
    static let jumpRope = RepDetectionConfiguration(
        topAngle: 172,
        descentAngle: 166,
        bottomAngle: 158,
        bottomExitAngle: 164,
        minimumRange: 14,
        stableFrameCount: 1,
        // Timed from takeoff to landing, which is only a tenth of a second or so.
        minimumRepDuration: 0.08,
        cooldown: 0.1,
        maximumTrackingGap: 0.8
    )
}

extension ExerciseType {
    var repConfiguration: RepDetectionConfiguration {
        switch self {
        case .squat: return .squat
        case .pushUp: return .pushUp
        case .lunge: return .lunge
        case .gluteBridge: return .gluteBridge
        case .sitUp: return .sitUp
        case .jumpingJack: return .jumpingJack
        case .jumpRope: return .jumpRope
        }
    }
}

final class RepDetectionEngine {
    private enum Stage: Equatable {
        case notReady
        case top
        case descending
        case bottom
        case ascending
    }

    private let configuration: RepDetectionConfiguration
    private let logger = Logger(subsystem: "com.repduo.ios", category: "rep.engine")
    private var stage: Stage = .notReady
    private var pendingStage: Stage?
    private var pendingFrames = 0
    private var cycleStartedAt: TimeInterval?
    private var minimumCycleAngle = 180.0
    private var lastRepAt = -Double.infinity
    private var lastProcessedAt = -Double.infinity
    private var trackingLostAt: TimeInterval?
    private var didResetForTrackingLoss = false

    private(set) var repCount = 0

    init(exercise: ExerciseType, configuration: RepDetectionConfiguration? = nil) {
        self.configuration = configuration ?? exercise.repConfiguration
    }

    func reset() {
        stage = .notReady
        pendingStage = nil
        pendingFrames = 0
        cycleStartedAt = nil
        minimumCycleAngle = 180
        lastRepAt = -.infinity
        lastProcessedAt = -.infinity
        trackingLostAt = nil
        didResetForTrackingLoss = false
        repCount = 0
    }

    func process(_ frame: PoseFrame) -> RepDetectionUpdate {
        guard frame.timestamp > lastProcessedAt else {
            return output(completedRep: false)
        }
        lastProcessedAt = frame.timestamp

        guard frame.quality.permitsCounting,
              frame.isFormAcceptable,
              let angle = frame.primaryAngle else {
            clearPendingTransition()
            if trackingLostAt == nil {
                trackingLostAt = frame.timestamp
                didResetForTrackingLoss = false
            }
            if let trackingLostAt,
               frame.timestamp - trackingLostAt >= configuration.maximumTrackingGap,
               !didResetForTrackingLoss {
                resetCycle()
                didResetForTrackingLoss = true
                logger.notice("Partial repetition reset after prolonged tracking loss")
            }
            return output(completedRep: false)
        }
        trackingLostAt = nil
        didResetForTrackingLoss = false

        var completedRep = false

        switch stage {
        case .notReady:
            transition(if: angle >= configuration.topAngle, to: .top)

        case .top:
            if angle <= configuration.descentAngle {
                if transition(if: true, to: .descending) {
                    cycleStartedAt = frame.timestamp
                    minimumCycleAngle = angle
                }
            } else {
                clearPendingTransition()
            }

        case .descending:
            minimumCycleAngle = min(minimumCycleAngle, angle)
            transition(if: angle <= configuration.bottomAngle, to: .bottom)

        case .bottom:
            minimumCycleAngle = min(minimumCycleAngle, angle)
            transition(if: angle >= configuration.bottomExitAngle, to: .ascending)

        case .ascending:
            minimumCycleAngle = min(minimumCycleAngle, angle)
            if angle >= configuration.topAngle,
               transition(if: true, to: .top),
               let cycleStartedAt,
               frame.timestamp - cycleStartedAt >= configuration.minimumRepDuration,
               frame.timestamp - lastRepAt >= configuration.cooldown,
               configuration.topAngle - minimumCycleAngle >= configuration.minimumRange {
                repCount += 1
                completedRep = true
                lastRepAt = frame.timestamp
                self.cycleStartedAt = nil
                minimumCycleAngle = 180
                logger.info("Repetition completed; total \(self.repCount, privacy: .public)")
            }
        }

        return output(completedRep: completedRep)
    }

    func registerDebugRep() -> RepDetectionUpdate {
        repCount += 1
        return RepDetectionUpdate(phase: .ready, repCount: repCount, completedRep: true)
    }

    @discardableResult
    private func transition(if condition: Bool, to newStage: Stage) -> Bool {
        guard condition else {
            clearPendingTransition()
            return false
        }
        if pendingStage == newStage {
            pendingFrames += 1
        } else {
            pendingStage = newStage
            pendingFrames = 1
        }
        guard pendingFrames >= configuration.stableFrameCount else { return false }
        stage = newStage
        clearPendingTransition()
        return true
    }

    private func clearPendingTransition() {
        pendingStage = nil
        pendingFrames = 0
    }

    private func resetCycle() {
        stage = .notReady
        cycleStartedAt = nil
        minimumCycleAngle = 180
        clearPendingTransition()
    }

    private func output(completedRep: Bool) -> RepDetectionUpdate {
        let phase: ExercisePhase
        switch stage {
        case .notReady, .top: phase = .ready
        case .descending: phase = .down
        case .bottom: phase = .hold
        case .ascending: phase = .up
        }
        return RepDetectionUpdate(phase: phase, repCount: repCount, completedRep: completedRep)
    }
}
