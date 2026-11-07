import Foundation

/// A recorded set that a later set races against: when each rep landed, and
/// the body's joints sampled through the set so the ghost can be drawn.
/// Times are seconds of active (unpaused) set time.
public struct GhostTrack: Codable, Equatable, Sendable {
    struct Pose: Codable, Equatable, Sendable {
        let time: Double
        /// Joint raw value to normalized [x, y], in the camera's Vision space.
        let points: [String: [Double]]
    }

    public let exercise: ExerciseType
    public let recordedAt: Date
    public let repTimes: [Double]
    public let duration: Double
    let poses: [Pose]

    public var repCount: Int { repTimes.count }

    /// Reps the ghost had finished `elapsed` seconds into the set.
    func reps(at elapsed: Double) -> Int {
        repTimes.prefix { $0 <= elapsed }.count
    }

    /// The ghost's joints at `elapsed`, blended between the two nearest samples.
    /// Nil before the first sample, after the set ended, or across a tracking gap.
    func pose(at elapsed: Double) -> [BodyJoint: JointPoint]? {
        guard let first = poses.first, let last = poses.last,
              elapsed >= first.time, elapsed <= last.time else { return nil }
        let nextIndex = poses.firstIndex { $0.time >= elapsed } ?? poses.count - 1
        let next = poses[nextIndex]
        let previous = poses[max(0, nextIndex - 1)]
        guard next.time - previous.time <= GhostRecorder.maximumGap else { return nil }
        let span = next.time - previous.time
        let blend = span > 0 ? (elapsed - previous.time) / span : 0
        var joints: [BodyJoint: JointPoint] = [:]
        for (name, end) in next.points {
            guard let joint = BodyJoint(rawValue: name), end.count == 2 else { continue }
            let start = previous.points[name] ?? end
            joints[joint] = JointPoint(
                x: start[0] + (end[0] - start[0]) * blend,
                y: start[1] + (end[1] - start[1]) * blend,
                confidence: 1
            )
        }
        return joints.isEmpty ? nil : joints
    }

    /// More reps wins; equal reps go to the quicker set.
    public func beats(_ other: GhostTrack?) -> Bool {
        guard let other else { return repCount > 0 }
        if repCount != other.repCount { return repCount > other.repCount }
        return duration < other.duration
    }
}

/// Where the live set stands against the ghost.
struct GhostRaceStatus: Equatable, Sendable {
    let ghostReps: Int
    let lead: Int
    /// The ghost has finished its set; from here the live set can only gain on it.
    let ghostFinished: Bool

    init(track: GhostTrack, liveReps: Int, elapsed: Double) {
        ghostReps = track.reps(at: elapsed)
        lead = liveReps - ghostReps
        ghostFinished = elapsed > track.duration
    }
}

/// Samples a live set into a `GhostTrack`.
struct GhostRecorder {
    /// About 15 poses a second keeps the ghost smooth and a minute-long set small.
    static let sampleInterval = 1.0 / 15
    /// Samples further apart than this are a tracking gap the ghost won't bridge.
    static let maximumGap = 0.5

    private var poses: [GhostTrack.Pose] = []
    private var repTimes: [Double] = []

    mutating func record(_ joints: [BodyJoint: JointPoint], at elapsed: Double) {
        // A few milliseconds of slack so a 30 fps camera lands on every other frame
        // instead of rounding past it.
        if let last = poses.last, elapsed - last.time < Self.sampleInterval - 0.004 { return }
        let points = joints
            .filter { $0.value.confidence >= PoseQualityEvaluator.minimumJointConfidence }
            .reduce(into: [String: [Double]]()) { result, entry in
                // Four decimals is well under a pixel and keeps the file compact.
                result[entry.key.rawValue] = [entry.value.x, entry.value.y].map { ($0 * 10_000).rounded() / 10_000 }
            }
        guard !points.isEmpty else { return }
        poses.append(GhostTrack.Pose(time: elapsed, points: points))
    }

    mutating func markRep(at elapsed: Double) {
        repTimes.append(elapsed)
    }

    func track(exercise: ExerciseType, duration: Double, recordedAt: Date) -> GhostTrack? {
        guard !repTimes.isEmpty else { return nil }
        return GhostTrack(
            exercise: exercise,
            recordedAt: recordedAt,
            repTimes: repTimes,
            duration: max(duration, repTimes.last ?? 0),
            poses: poses
        )
    }
}
