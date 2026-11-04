import Foundation

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case squat
    case pushUp

    var displayName: String {
        switch self {
        case .squat: return "SQUAT".rdLocalized
        case .pushUp: return "PUSH-UP".rdLocalized
        }
    }

    /// Untranslated label for condensed scoreboard captions.
    var scoreboardName: String {
        switch self {
        case .squat: return "SQUAT"
        case .pushUp: return "PUSH-UP"
        }
    }

    var shortInstruction: String {
        switch self {
        case .squat: return "Head, hips, knees and ankles in frame.".rdLocalized
        case .pushUp: return "Face the camera with your full body visible.".rdLocalized
        }
    }

    var demoImageName: String {
        switch self {
        case .squat: return "SquatDemo"
        case .pushUp: return "PushUpDemo"
        }
    }

    var symbolName: String {
        switch self {
        case .squat: return "figure.strengthtraining.traditional"
        case .pushUp: return "figure.core.training"
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
        case (.fullBody, .squat): return "GET YOUR FULL\nBODY IN FRAME.".rdLocalized
        case (.fullBody, .pushUp): return "FACE THE CAMERA\nIN PUSH-UP POSITION.".rdLocalized
        case (.partialBody, .squat): return "FRAME YOUR\nLOWER BODY.".rdLocalized
        case (.partialBody, .pushUp): return "FRAME YOUR\nUPPER BODY.".rdLocalized
        }
    }

    func instruction(for exercise: ExerciseType) -> String {
        switch (self, exercise) {
        case (.fullBody, .squat): return "Head, hips, knees and ankles in frame.".rdLocalized
        case (.fullBody, .pushUp): return "Face the camera with your full body visible.".rdLocalized
        case (.partialBody, .squat): return "Keep one hip, knee and ankle in frame.".rdLocalized
        case (.partialBody, .pushUp): return "Face the camera with both shoulders, elbows and wrists visible.".rdLocalized
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
        case .multiplePeople: return "Only one person can train at a time.".rdLocalized
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
        learnedBaseline: MovementBaseline? = nil
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
    }

    var averageTempo: TimeInterval? {
        repCount > 0 ? activeDuration / Double(repCount) : nil
    }
}
