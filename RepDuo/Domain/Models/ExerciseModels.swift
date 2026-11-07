import Foundation

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case squat
    case pushUp
    case lunge
    case gluteBridge
    case sitUp
    case jumpingJack
    case jumpRope

    var displayName: String { scoreboardName.rdLocalized }

    /// Untranslated label for condensed scoreboard captions.
    var scoreboardName: String {
        switch self {
        case .squat: return "SQUAT"
        case .pushUp: return "PUSH-UP"
        case .lunge: return "LUNGE"
        case .gluteBridge: return "GLUTE BRIDGE"
        case .sitUp: return "SIT-UP"
        case .jumpingJack: return "JUMPING JACK"
        case .jumpRope: return "JUMP ROPE"
        }
    }

    /// Floor moves are filmed lying down, so framing checks use the longer body axis.
    var isFloorMove: Bool {
        switch self {
        case .pushUp, .gluteBridge, .sitUp: return true
        case .squat, .lunge, .jumpingJack, .jumpRope: return false
        }
    }

    /// Asset for demo mode; only some moves ship a reference photo.
    var demoImageName: String? {
        switch self {
        case .squat: return "SquatDemo"
        case .pushUp: return "PushUpDemo"
        case .lunge, .gluteBridge, .sitUp, .jumpingJack, .jumpRope: return nil
        }
    }
}

public enum BodyTrackingMode: String, Codable, CaseIterable, Sendable {
    case fullBody
    case partialBody

    var segmentTitle: String {
        switch self {
        case .fullBody: return "FULL BODY · ACCURATE".rdLocalized
        case .partialBody: return "PARTIAL BODY · ROUGH".rdLocalized
        }
    }

    func setupTitle(for exercise: ExerciseType) -> String {
        switch (self, exercise) {
        case (.fullBody, .pushUp): return "FACE THE CAMERA\nIN PUSH-UP POSITION.".rdLocalized
        case (.fullBody, .jumpingJack), (.fullBody, .jumpRope): return "FACE THE CAMERA\nWITH ROOM TO JUMP.".rdLocalized
        case (.fullBody, .gluteBridge), (.fullBody, .sitUp): return "LIE SIDE-ON\nTO THE PHONE.".rdLocalized
        case (.fullBody, _): return "GET YOUR FULL\nBODY IN FRAME.".rdLocalized
        case (.partialBody, .squat), (.partialBody, .lunge): return "FRAME YOUR\nLOWER BODY.".rdLocalized
        case (.partialBody, .pushUp), (.partialBody, .jumpingJack), (.partialBody, .jumpRope):
            return "FRAME YOUR\nUPPER BODY.".rdLocalized
        case (.partialBody, .gluteBridge), (.partialBody, .sitUp): return "FRAME YOUR\nWORKING SIDE.".rdLocalized
        }
    }

    func instruction(for exercise: ExerciseType) -> String {
        switch (self, exercise) {
        case (.fullBody, .squat): return "Head, hips, knees and ankles in frame.".rdLocalized
        case (.fullBody, .pushUp): return "Face the camera with your full body visible.".rdLocalized
        case (.fullBody, .lunge): return "Stand side-on with head, hips, knees and ankles in frame.".rdLocalized
        case (.fullBody, .gluteBridge), (.fullBody, .sitUp):
            return "Lie side-on with shoulders, hips, knees and ankles in frame.".rdLocalized
        case (.fullBody, .jumpingJack): return "Face the camera with arms and feet in frame.".rdLocalized
        case (.fullBody, .jumpRope): return "Face the camera with shoulders, hips and feet in frame.".rdLocalized
        case (.partialBody, .squat), (.partialBody, .lunge): return "Keep one hip, knee and ankle in frame.".rdLocalized
        case (.partialBody, .pushUp): return "Face the camera with both shoulders, elbows and wrists visible.".rdLocalized
        case (.partialBody, .gluteBridge), (.partialBody, .sitUp):
            return "Keep one shoulder, hip and knee in frame.".rdLocalized
        case (.partialBody, .jumpingJack): return "Face the camera with shoulders, wrists and hips visible.".rdLocalized
        case (.partialBody, .jumpRope): return "Face the camera with shoulders and hips visible.".rdLocalized
        }
    }
}

enum ExercisePhase: String, Codable, Sendable {
    case ready = "READY"
    case down = "DOWN"
    case hold = "HOLD"
    case up = "UP"

    var displayName: String { rawValue.rdLocalized }
}

enum PoseQuality: Equatable, Sendable {
    case excellent
    case usable
    case unstable
    case missingRequiredJoints
    case multiplePeople

    var permitsCounting: Bool {
        self == .excellent || self == .usable
    }

    var message: String {
        switch self {
        case .excellent: return "Locked on. Keep moving.".rdLocalized
        case .usable: return "Tracking. Keep the required joints visible.".rdLocalized
        case .unstable: return "Hold steady and improve the light.".rdLocalized
        case .missingRequiredJoints: return "Adjust the phone so the required joints are visible.".rdLocalized
        case .multiplePeople: return "Several people look alike to the camera. Step apart so RepDuo can lock onto you.".rdLocalized
        }
    }

    var debugName: String {
        switch self {
        case .excellent: return "excellent"
        case .usable: return "usable"
        case .unstable: return "unstable"
        case .missingRequiredJoints: return "missing"
        case .multiplePeople: return "multiple"
        }
    }
}

enum RendererQuality: String, Sendable {
    case high
    case balanced
    case lowPower
    case thermalSafe
}

public struct WorkoutSummary: Equatable, Sendable {
    public let id: UUID
    public let exercise: ExerciseType
    public let startedAt: Date
    public let endedAt: Date
    public let repCount: Int
    public let activeDuration: TimeInterval
    public let averageHeartRate: Double?
    public let maximumHeartRate: Double?
    public let lowConfidenceEventCount: Int
    public let algorithmVersion: String
    public let coachingReport: WorkoutCoachingReport?
    public let learnedBaseline: MovementBaseline?
    /// Stars and streaks from the live set; not persisted, like the coaching report.
    public let rewards: SetRewards?

    public init(
        id: UUID = UUID(),
        exercise: ExerciseType,
        startedAt: Date,
        endedAt: Date,
        repCount: Int,
        activeDuration: TimeInterval,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        lowConfidenceEventCount: Int = 0,
        algorithmVersion: String = "coach-rules-1.0",
        coachingReport: WorkoutCoachingReport? = nil,
        learnedBaseline: MovementBaseline? = nil,
        rewards: SetRewards? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.repCount = repCount
        self.activeDuration = activeDuration
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.lowConfidenceEventCount = lowConfidenceEventCount
        self.algorithmVersion = algorithmVersion
        self.coachingReport = coachingReport
        self.learnedBaseline = learnedBaseline
        self.rewards = rewards
    }

    var averageTempo: TimeInterval? {
        repCount > 0 ? activeDuration / Double(repCount) : nil
    }
}
