import Foundation

public struct MovementBaseline: Codable, Equatable, Sendable {
    public private(set) var sampleCount: Int
    public private(set) var averageRange: Double
    public private(set) var averageDuration: TimeInterval

    public init(
        sampleCount: Int = 0,
        averageRange: Double = 0,
        averageDuration: TimeInterval = 0
    ) {
        self.sampleCount = max(0, sampleCount)
        self.averageRange = max(0, averageRange)
        self.averageDuration = max(0, averageDuration)
    }

    public var isPersonalized: Bool { sampleCount >= 3 }

    mutating func learn(range: Double, duration: TimeInterval, score: Int?) {
        guard range.isFinite, range > 0, duration.isFinite, duration > 0 else { return }

        if sampleCount < 3 {
            let count = Double(sampleCount)
            averageRange = (averageRange * count + range) / (count + 1)
            averageDuration = (averageDuration * count + duration) / (count + 1)
            sampleCount += 1
            return
        }

        // Adapt slowly, and only to solid repetitions, so fatigue or a bad set
        // cannot teach the coach that deteriorating form is the new normal.
        guard (score ?? 0) >= 80 else { return }
        averageRange = averageRange * 0.95 + range * 0.05
        averageDuration = averageDuration * 0.95 + duration * 0.05
        sampleCount = min(50, sampleCount + 1)
    }
}

enum MovementIssue: String, Codable, CaseIterable, Equatable, Sendable {
    case shallowRange
    case rushedTempo
    case asymmetry
    case bodyAlignment
    case rangeFading

    var title: String {
        switch self {
        case .shallowRange: return "Range is too short".rdLocalized
        case .rushedTempo: return "Movement is rushed".rdLocalized
        case .asymmetry: return "Sides are out of sync".rdLocalized
        case .bodyAlignment: return "Body line is unstable".rdLocalized
        case .rangeFading: return "Range is fading".rdLocalized
        }
    }

    var liveCue: String {
        switch self {
        case .shallowRange: return "Use a fuller range.".rdLocalized
        case .rushedTempo: return "Slow down and stay controlled.".rdLocalized
        case .asymmetry: return "Keep both sides moving together.".rdLocalized
        case .bodyAlignment: return "Keep your body in one straight line.".rdLocalized
        case .rangeFading: return "Your range is fading. Protect your form.".rdLocalized
        }
    }

    var summaryAdvice: String {
        switch self {
        case .shallowRange:
            return "Prioritize a complete range before adding more reps.".rdLocalized
        case .rushedTempo:
            return "Use a steadier tempo so every rep stays controlled.".rdLocalized
        case .asymmetry:
            return "Keep your left and right sides moving together.".rdLocalized
        case .bodyAlignment:
            return "Brace your trunk and keep one strong body line.".rdLocalized
        case .rangeFading:
            return "Your range decreased late in the set. Consider ending the next set earlier.".rdLocalized
        }
    }
}

struct RepCoachingResult: Equatable, Sendable {
    let repNumber: Int
    let score: Int?
    let rangeScore: Int?
    let tempoScore: Int?
    let symmetryScore: Int?
    let primaryIssue: MovementIssue?
    let confidence: Double
    let range: Double
    let duration: TimeInterval
    let baselineProgress: Int
    let isPersonalized: Bool
    let shouldSpeak: Bool

    var statusText: String {
        guard let score else {
            return "Rep counted, but visibility was too low to score it.".rdLocalized
        }
        let result = primaryIssue?.liveCue ?? "Good form. Keep this rhythm.".rdLocalized
        if isPersonalized {
            return "%d/100 · %@".rdLocalizedFormat(score, result)
        }
        return "LEARNING %d/3 · %d/100 · %@".rdLocalizedFormat(baselineProgress, score, result)
    }
}

public struct WorkoutCoachingReport: Equatable, Sendable {
    public let averageScore: Int?
    public let scoredRepCount: Int
    public let goodRepCount: Int
    public let unscoredRepCount: Int
    public let isPersonalized: Bool
    let primaryIssue: MovementIssue?
    let detectedFatigue: Bool

    var insight: String {
        guard scoredRepCount > 0 else {
            return "Tracking was not clear enough to score this set.".rdLocalized
        }
        if detectedFatigue {
            return MovementIssue.rangeFading.summaryAdvice
        }
        if let primaryIssue {
            return primaryIssue.summaryAdvice
        }
        return "Your form stayed consistent. Keep this baseline.".rdLocalized
    }
}

final class MovementCoach {
    private struct FrameSample {
        let timestamp: TimeInterval
        let angle: Double
        let confidence: Double
        let symmetryError: Double?
        let alignmentError: Double?
    }

    private struct ScoredIssue {
        let issue: MovementIssue
        let penalty: Double
    }

    private let exercise: ExerciseType
    private let trackingMode: BodyTrackingMode
    private var samples: [FrameSample] = []
    private var lastPhase: ExercisePhase = .ready
    private var assessments: [RepCoachingResult] = []
    private var lastIssue: MovementIssue?
    private var consecutiveIssueCount = 0

    private(set) var baseline: MovementBaseline

    init(
        exercise: ExerciseType,
        trackingMode: BodyTrackingMode,
        baseline: MovementBaseline? = nil
    ) {
        self.exercise = exercise
        self.trackingMode = trackingMode
        self.baseline = baseline ?? MovementBaseline()
    }

    func process(
        frame: PoseFrame,
        phase: ExercisePhase,
        completedRep: Bool,
        repNumber: Int
    ) -> RepCoachingResult? {
        if phase == .down, lastPhase == .ready {
            samples.removeAll(keepingCapacity: true)
        }

        if phase != .ready || !samples.isEmpty {
            if let sample = makeSample(from: frame) {
                samples.append(sample)
            }
        }

        defer { lastPhase = phase }

        if completedRep {
            let result = assess(repNumber: repNumber)
            samples.removeAll(keepingCapacity: true)
            assessments.append(result)
            return result
        }

        // Returning to ready without completing means tracking loss invalidated
        // a partial repetition. Never let those frames contaminate the next rep.
        if phase == .ready, lastPhase != .ready {
            samples.removeAll(keepingCapacity: true)
        }
        return nil
    }

    func registerDebugRep(repNumber: Int, timestamp: TimeInterval) -> RepCoachingResult {
        let range = defaultExpectedRange
        let duration = max(1.2, baseline.averageDuration)
        let wasPersonalized = baseline.isPersonalized
        let score = 94
        baseline.learn(range: range, duration: duration, score: score)
        let result = RepCoachingResult(
            repNumber: repNumber,
            score: score,
            rangeScore: 94,
            tempoScore: 92,
            symmetryScore: 96,
            primaryIssue: nil,
            confidence: 0.95,
            range: range,
            duration: duration,
            baselineProgress: min(3, baseline.sampleCount),
            isPersonalized: wasPersonalized,
            shouldSpeak: false
        )
        assessments.append(result)
        return result
    }

    func report() -> WorkoutCoachingReport {
        let scores = assessments.compactMap(\.score)
        let average = scores.isEmpty
            ? nil
            : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        let issues = assessments.compactMap(\.primaryIssue)
        let primaryIssue = MovementIssue.allCases.max { first, second in
            issues.filter { $0 == first }.count < issues.filter { $0 == second }.count
        }.flatMap { issue in issues.contains(issue) ? issue : nil }
        let scoredRanges = assessments.filter { $0.score != nil }.map(\.range)
        let detectedFatigue = Self.isRangeFading(scoredRanges)

        return WorkoutCoachingReport(
            averageScore: average,
            scoredRepCount: scores.count,
            goodRepCount: scores.filter { $0 >= 80 }.count,
            unscoredRepCount: assessments.count - scores.count,
            isPersonalized: baseline.isPersonalized,
            primaryIssue: detectedFatigue ? .rangeFading : primaryIssue,
            detectedFatigue: detectedFatigue
        )
    }

    private func assess(repNumber: Int) -> RepCoachingResult {
        let reliableSamples = samples.filter { $0.confidence >= 0.48 }
        guard reliableSamples.count >= 3,
              let first = reliableSamples.first,
              let last = reliableSamples.last else {
            resetIssueStreak()
            return RepCoachingResult(
                repNumber: repNumber,
                score: nil,
                rangeScore: nil,
                tempoScore: nil,
                symmetryScore: nil,
                primaryIssue: nil,
                confidence: 0,
                range: 0,
                duration: 0,
                baselineProgress: min(3, baseline.sampleCount),
                isPersonalized: baseline.isPersonalized,
                shouldSpeak: false
            )
        }

        let confidence = reliableSamples.map(\.confidence).reduce(0, +) / Double(reliableSamples.count)
        let angles = reliableSamples.map(\.angle)
        let range = (angles.max() ?? 0) - (angles.min() ?? 0)
        let duration = max(0, last.timestamp - first.timestamp)
        let wasPersonalized = baseline.isPersonalized

        guard confidence >= 0.52, range.isFinite, duration >= 0.35 else {
            resetIssueStreak()
            return RepCoachingResult(
                repNumber: repNumber,
                score: nil,
                rangeScore: nil,
                tempoScore: nil,
                symmetryScore: nil,
                primaryIssue: nil,
                confidence: confidence,
                range: range,
                duration: duration,
                baselineProgress: min(3, baseline.sampleCount),
                isPersonalized: wasPersonalized,
                shouldSpeak: false
            )
        }

        let expectedRange = wasPersonalized
            ? max(defaultExpectedRange * 0.82, baseline.averageRange * 0.90)
            : defaultExpectedRange
        let minimumDuration = wasPersonalized
            ? max(fastestControlledRep * 0.9, baseline.averageDuration * 0.65)
            : fastestControlledRep
        let symmetryError = average(reliableSamples.compactMap(\.symmetryError))
        let alignmentError = average(reliableSamples.compactMap(\.alignmentError))
        let rangeRatio = range / max(1, expectedRange)
        let rangeScore = max(40, min(100, Int((rangeRatio * 100).rounded())))
        let tempoScore: Int
        if duration < minimumDuration {
            tempoScore = max(40, min(100, Int((duration / minimumDuration * 100).rounded())))
        } else if wasPersonalized, baseline.averageDuration > 0 {
            let deviation = abs(duration - baseline.averageDuration) / baseline.averageDuration
            tempoScore = max(65, min(100, Int((100 - deviation * 35).rounded())))
        } else {
            tempoScore = 94
        }
        let symmetryScore = symmetryError.map {
            max(40, min(100, Int((100 - $0 * 1.35).rounded())))
        }

        var issues: [ScoredIssue] = []
        if rangeRatio < 0.90 {
            issues.append(ScoredIssue(
                issue: .shallowRange,
                penalty: min(32, 12 + (0.90 - rangeRatio) * 80)
            ))
        }
        if duration < minimumDuration {
            issues.append(ScoredIssue(
                issue: .rushedTempo,
                penalty: min(22, 10 + (minimumDuration - duration) * 18)
            ))
        }
        if let symmetry = symmetryError,
           symmetry > symmetryThreshold {
            issues.append(ScoredIssue(
                issue: .asymmetry,
                penalty: min(24, 10 + (symmetry - symmetryThreshold) * 0.7)
            ))
        }
        if trackingMode == .fullBody,
           let alignment = alignmentError,
           alignment > alignmentThreshold {
            issues.append(ScoredIssue(
                issue: .bodyAlignment,
                penalty: min(24, 10 + (alignment - alignmentThreshold) * 90)
            ))
        }

        let score = max(40, min(100, Int((100 - issues.map(\.penalty).reduce(0, +)).rounded())))
        let primaryIssue = issues.max(by: { $0.penalty < $1.penalty })?.issue
        let shouldSpeak = updateIssueStreak(primaryIssue)

        baseline.learn(range: range, duration: duration, score: score)
        return RepCoachingResult(
            repNumber: repNumber,
            score: score,
            rangeScore: rangeScore,
            tempoScore: tempoScore,
            symmetryScore: symmetryScore,
            primaryIssue: primaryIssue,
            confidence: confidence,
            range: range,
            duration: duration,
            baselineProgress: min(3, baseline.sampleCount),
            isPersonalized: wasPersonalized,
            shouldSpeak: shouldSpeak
        )
    }

    private func makeSample(from frame: PoseFrame) -> FrameSample? {
        guard frame.quality.permitsCounting, let angle = frame.primaryAngle else { return nil }
        let confidence = PoseQualityEvaluator.evaluate(
            exercise: exercise,
            joints: frame.joints,
            trackingMode: trackingMode
        ).averageConfidence ?? qualityFallback(frame.quality)
        return FrameSample(
            timestamp: frame.timestamp,
            angle: angle,
            confidence: confidence,
            symmetryError: symmetryError(in: frame.joints),
            alignmentError: alignmentError(in: frame.joints)
        )
    }

    private func symmetryError(in joints: [BodyJoint: JointPoint]) -> Double? {
        switch exercise {
        case .squat:
            return angleDifference(
                first: (.leftHip, .leftKnee, .leftAnkle),
                second: (.rightHip, .rightKnee, .rightAnkle),
                joints: joints
            )
        case .pushUp:
            return angleDifference(
                first: (.leftShoulder, .leftElbow, .leftWrist),
                second: (.rightShoulder, .rightElbow, .rightWrist),
                joints: joints
            )
        case .jumpingJack:
            return angleDifference(
                first: (.leftHip, .leftShoulder, .leftWrist),
                second: (.rightHip, .rightShoulder, .rightWrist),
                joints: joints
            )
        case .lunge, .gluteBridge, .sitUp, .jumpRope:
            // Skipping has no joint pair to compare. Lunges are asymmetric by design; floor moves are filmed side-on with one side hidden.
            return nil
        }
    }

    private func alignmentError(in joints: [BodyJoint: JointPoint]) -> Double? {
        guard exercise == .pushUp, trackingMode == .fullBody else { return nil }
        if let leftShoulder = joints[.leftShoulder],
           let rightShoulder = joints[.rightShoulder],
           abs(leftShoulder.x - rightShoulder.x) >= 0.08,
           let leftHip = joints[.leftHip],
           let rightHip = joints[.rightHip] {
            return max(abs(leftShoulder.y - rightShoulder.y), abs(leftHip.y - rightHip.y))
        }

        let candidates: [(BodyJoint, BodyJoint, BodyJoint)] = [
            (.leftShoulder, .leftHip, .leftAnkle),
            (.rightShoulder, .rightHip, .rightAnkle)
        ]
        return candidates.compactMap { shoulder, hip, ankle -> Double? in
            guard let shoulder = joints[shoulder],
                  let hip = joints[hip],
                  let ankle = joints[ankle] else { return nil }
            return PoseGeometry.distanceFromLine(hip, lineStart: shoulder, lineEnd: ankle)
        }.min()
    }

    private func angleDifference(
        first: (BodyJoint, BodyJoint, BodyJoint),
        second: (BodyJoint, BodyJoint, BodyJoint),
        joints: [BodyJoint: JointPoint]
    ) -> Double? {
        guard let a1 = joints[first.0], let a2 = joints[first.1], let a3 = joints[first.2],
              let b1 = joints[second.0], let b2 = joints[second.1], let b3 = joints[second.2] else { return nil }
        let firstAngle = PoseGeometry.angle(a1, vertex: a2, a3)
        let secondAngle = PoseGeometry.angle(b1, vertex: b2, b3)
        return abs(firstAngle - secondAngle)
    }

    private func updateIssueStreak(_ issue: MovementIssue?) -> Bool {
        guard let issue else {
            resetIssueStreak()
            return false
        }
        if issue == lastIssue {
            consecutiveIssueCount += 1
        } else {
            lastIssue = issue
            consecutiveIssueCount = 1
        }
        return consecutiveIssueCount == 2
    }

    private func resetIssueStreak() {
        lastIssue = nil
        consecutiveIssueCount = 0
    }

    private var defaultExpectedRange: Double {
        switch exercise {
        case .squat: return 65
        case .pushUp: return 70
        case .lunge: return 52
        case .gluteBridge: return 36
        case .sitUp: return 52
        case .jumpingJack: return 95
        case .jumpRope: return 18
        }
    }

    private var symmetryThreshold: Double {
        switch exercise {
        case .squat: return 18
        case .jumpingJack: return 28
        case .pushUp, .lunge, .gluteBridge, .sitUp, .jumpRope: return 22
        }
    }

    /// Below this a rep counts as rushed. Skipping and jumping jacks are meant to be quick.
    private var fastestControlledRep: TimeInterval {
        switch exercise {
        case .jumpRope: return 0.25
        case .jumpingJack: return 0.45
        case .squat, .pushUp, .lunge, .gluteBridge, .sitUp: return 0.72
        }
    }

    private var alignmentThreshold: Double { 0.09 }

    private func qualityFallback(_ quality: PoseQuality) -> Double {
        switch quality {
        case .excellent: return 0.78
        case .usable: return 0.55
        case .unstable, .missingRequiredJoints, .multiplePeople: return 0
        }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func isRangeFading(_ ranges: [Double]) -> Bool {
        guard ranges.count >= 6 else { return false }
        let window = max(2, ranges.count / 3)
        let early = Array(ranges.prefix(window))
        let late = Array(ranges.suffix(window))
        let earlyAverage = early.reduce(0, +) / Double(early.count)
        let lateAverage = late.reduce(0, +) / Double(late.count)
        return earlyAverage > 0 && lateAverage < earlyAverage * 0.84
    }
}
