import Foundation

/// Axis-aligned box in Vision's normalized coordinate space.
struct NormalizedBounds: Equatable, Sendable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var area: Double { width * height }
    var centerX: Double { (minX + maxX) / 2 }
    var centerY: Double { (minY + maxY) / 2 }

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init?(points: [JointPoint]) {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        self.init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    func intersectionOverUnion(with other: NormalizedBounds) -> Double {
        let width = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let height = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        let intersection = width * height
        let union = area + other.area - intersection
        guard union > .ulpOfOne else { return 0 }
        return intersection / union
    }
}

/// One detected body, reduced to what identity matching needs.
struct PoseCandidate: Equatable, Sendable {
    let joints: [BodyJoint: JointPoint]
    let bounds: NormalizedBounds
    let meanConfidence: Double
    /// Body size that stays fairly constant through a squat or push-up: the
    /// longest of torso length, shoulder width, and the box diagonal's half.
    let scale: Double

    init?(joints: [BodyJoint: JointPoint]) {
        guard let bounds = NormalizedBounds(points: Array(joints.values)) else { return nil }
        self.joints = joints
        self.bounds = bounds
        meanConfidence = joints.values.map(\.confidence).reduce(0, +) / Double(joints.count)
        scale = max(
            Self.torsoLength(joints) ?? 0,
            Self.distance(joints[.leftShoulder], joints[.rightShoulder]) ?? 0,
            hypot(bounds.width, bounds.height) / 2
        )
    }

    private static func torsoLength(_ joints: [BodyJoint: JointPoint]) -> Double? {
        let shoulders = midpoint(joints[.leftShoulder], joints[.rightShoulder]) ?? joints[.neck]
        let hips = midpoint(joints[.leftHip], joints[.rightHip])
        return distance(shoulders, hips)
    }

    private static func midpoint(_ first: JointPoint?, _ second: JointPoint?) -> JointPoint? {
        switch (first, second) {
        case let (first?, second?):
            return JointPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2, confidence: min(first.confidence, second.confidence))
        case let (point?, nil), let (nil, point?):
            return point
        case (nil, nil):
            return nil
        }
    }

    private static func distance(_ first: JointPoint?, _ second: JointPoint?) -> Double? {
        guard let first, let second else { return nil }
        return hypot(first.x - second.x, first.y - second.y)
    }
}

enum TargetTrackingStatus: Equatable, Sendable {
    /// No one suitable is in view.
    case searching
    /// The trainee is identified for this frame.
    case locked
    /// Several people are equally plausible, so no one is counted.
    case ambiguous
}

struct TargetTrackingResult: Equatable, Sendable {
    let status: TargetTrackingStatus
    /// Index into the candidate list passed to `update`, when locked.
    let targetIndex: Int?
    /// Plausible bodies in view other than the trainee.
    let bystanderCount: Int
    /// Increments whenever a new person is acquired, so per-person filters can reset.
    let trackID: Int
}

struct TargetTrackingConfiguration: Equatable, Sendable {
    /// Detections with fewer joints are fragments (a stray hand or face) and are ignored.
    var minimumJointCount = 4
    var minimumMeanConfidence = 0.3
    var minimumScale = 0.06
    /// On first lock the most prominent person must beat the runner-up by this factor.
    var acquisitionDominance = 1.5
    /// Frame-to-frame match gate, in multiples of the trainee's body scale.
    var maximumCenterJump = 1.2
    var maximumScaleChange = 1.6
    /// Matches whose costs are this close are treated as indistinguishable.
    var ambiguityMargin = 0.35
    /// How long the trainee may be hidden before the lock is released.
    var lostTimeout: TimeInterval = 1.5
    /// After a release, re-acquisition prefers someone the trainee's size for this long.
    var reacquisitionMemory: TimeInterval = 6
    var velocitySmoothing = 0.5
}

/// Keeps counting attached to one person when others walk through the frame.
///
/// The most prominent, centered person is locked on first sight; afterwards each
/// frame is matched to that person by predicted position, overlap, and body
/// scale. Bystanders are ignored rather than stopping the workout, and counting
/// only pauses when two bodies are too close to tell apart.
final class TargetPersonTracker {
    private struct Track {
        var bounds: NormalizedBounds
        var scale: Double
        var velocityX: Double
        var velocityY: Double
        var lastSeenAt: TimeInterval
    }

    private let configuration: TargetTrackingConfiguration
    private var track: Track?
    private var releasedScale: Double?
    private var releasedAt: TimeInterval?
    private var trackID = 0

    init(configuration: TargetTrackingConfiguration = TargetTrackingConfiguration()) {
        self.configuration = configuration
    }

    var isLocked: Bool { track != nil }

    func reset() {
        track = nil
        releasedScale = nil
        releasedAt = nil
    }

    func update(candidates: [PoseCandidate], at timestamp: TimeInterval) -> TargetTrackingResult {
        let viable = candidates.indices.filter { isViable(candidates[$0]) }

        if var current = track {
            let dt = max(0, timestamp - current.lastSeenAt)
            let scored = viable.compactMap { index -> (index: Int, cost: Double)? in
                matchCost(candidates[index], track: current, elapsed: dt).map { (index, $0) }
            }.sorted { $0.cost < $1.cost }

            if let best = scored.first {
                if scored.count > 1, scored[1].cost - best.cost < configuration.ambiguityMargin {
                    return result(.ambiguous, target: nil, viableCount: viable.count)
                }
                let candidate = candidates[best.index]
                if dt > .ulpOfOne {
                    let alpha = configuration.velocitySmoothing
                    current.velocityX += ((candidate.bounds.centerX - current.bounds.centerX) / dt - current.velocityX) * alpha
                    current.velocityY += ((candidate.bounds.centerY - current.bounds.centerY) / dt - current.velocityY) * alpha
                }
                current.bounds = candidate.bounds
                current.scale += (candidate.scale - current.scale) * 0.2
                current.lastSeenAt = timestamp
                track = current
                return result(.locked, target: best.index, viableCount: viable.count)
            }

            guard dt >= configuration.lostTimeout else {
                return result(.searching, target: nil, viableCount: viable.count)
            }
            releasedScale = current.scale
            releasedAt = timestamp
            track = nil
        }

        return acquire(from: viable, candidates: candidates, at: timestamp)
    }

    private func acquire(from viable: [Int], candidates: [PoseCandidate], at timestamp: TimeInterval) -> TargetTrackingResult {
        var eligible = viable
        if let releasedScale, let releasedAt, timestamp - releasedAt <= configuration.reacquisitionMemory {
            eligible = eligible.filter { scaleRatio(candidates[$0].scale, releasedScale) <= configuration.maximumScaleChange }
        }
        let ranked = eligible
            .map { (index: $0, score: prominence(of: candidates[$0])) }
            .sorted { $0.score > $1.score }
        guard let best = ranked.first else {
            return result(.searching, target: nil, viableCount: viable.count)
        }
        if ranked.count > 1, best.score < ranked[1].score * configuration.acquisitionDominance {
            return result(.ambiguous, target: nil, viableCount: viable.count)
        }

        let candidate = candidates[best.index]
        track = Track(bounds: candidate.bounds, scale: candidate.scale, velocityX: 0, velocityY: 0, lastSeenAt: timestamp)
        releasedScale = nil
        releasedAt = nil
        trackID += 1
        return result(.locked, target: best.index, viableCount: viable.count)
    }

    private func isViable(_ candidate: PoseCandidate) -> Bool {
        candidate.joints.count >= configuration.minimumJointCount
            && candidate.meanConfidence >= configuration.minimumMeanConfidence
            && candidate.scale >= configuration.minimumScale
    }

    /// Larger, more central, more confident bodies are more likely the trainee
    /// who just set the phone up in front of themselves.
    private func prominence(of candidate: PoseCandidate) -> Double {
        let centerOffset = abs(candidate.bounds.centerX - 0.5)
        let centering = max(0.2, 1 - centerOffset * 1.4)
        return candidate.scale * centering * candidate.meanConfidence
    }

    private func matchCost(_ candidate: PoseCandidate, track: Track, elapsed: TimeInterval) -> Double? {
        let ratio = scaleRatio(candidate.scale, track.scale)
        guard ratio <= configuration.maximumScaleChange else { return nil }

        let horizon = min(elapsed, 0.5)
        let predictedX = track.bounds.centerX + track.velocityX * horizon
        let predictedY = track.bounds.centerY + track.velocityY * horizon
        let jump = hypot(candidate.bounds.centerX - predictedX, candidate.bounds.centerY - predictedY) / max(track.scale, 0.05)
        let overlap = candidate.bounds.intersectionOverUnion(with: track.bounds)
        guard jump <= configuration.maximumCenterJump || overlap >= 0.3 else { return nil }

        return jump + (1 - overlap) + log(ratio)
    }

    private func scaleRatio(_ first: Double, _ second: Double) -> Double {
        guard first > .ulpOfOne, second > .ulpOfOne else { return .infinity }
        return max(first, second) / min(first, second)
    }

    private func result(_ status: TargetTrackingStatus, target: Int?, viableCount: Int) -> TargetTrackingResult {
        TargetTrackingResult(
            status: status,
            targetIndex: target,
            bystanderCount: max(0, viableCount - (target == nil ? 0 : 1)),
            trackID: trackID
        )
    }
}
