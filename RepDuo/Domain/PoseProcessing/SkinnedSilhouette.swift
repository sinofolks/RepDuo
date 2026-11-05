import Foundation
import simd

/// Single-channel image, row 0 at the top, values in 0...1.
struct GrayImage: Equatable, Sendable {
    let width: Int
    let height: Int
    var pixels: [Float]

    init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height, "pixel count must match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> Float { pixels[y * width + x] }

    /// Width over height; used to measure angles in undistorted space.
    var aspect: Float { Float(width) / Float(max(height, 1)) }
}

/// A clean reference silhouette captured while the trainee held still,
/// together with the pose it was captured in.
struct SilhouetteCalibration: Equatable, Sendable {
    let exercise: ExerciseType
    let mask: GrayImage
    let joints: [BodyJoint: JointPoint]
    /// Primary angle at capture: the trainee's own "top" for depth progress.
    let referenceAngle: Double?
    let bodyScale: Double
    /// Camera image width over height. Segmentation masks can use a different
    /// aspect than the image, so angles are measured in image proportions.
    let imageAspect: Float
}

/// Averages masks over a short still period so one noisy segmentation frame
/// cannot shape the reference outline.
final class SilhouetteCalibrator {
    private let requiredFrames: Int
    private let maximumJointDrift: Double
    private var sum: [Float] = []
    private var size: (width: Int, height: Int)?
    private var anchorJoints: [BodyJoint: JointPoint] = [:]
    private var jointSums: [BodyJoint: (x: Double, y: Double, confidence: Double, count: Int)] = [:]
    private var angles: [Double] = []
    private var frames = 0

    init(requiredFrames: Int = 10, maximumJointDrift: Double = 0.03) {
        self.requiredFrames = max(1, requiredFrames)
        self.maximumJointDrift = maximumJointDrift
    }

    var progress: Double { Double(frames) / Double(requiredFrames) }

    func reset() {
        sum = []
        size = nil
        anchorJoints = [:]
        jointSums = [:]
        angles = []
        frames = 0
    }

    /// Adds one still frame; returns the calibration once enough agree.
    func add(
        mask: GrayImage,
        joints: [BodyJoint: JointPoint],
        angle: Double?,
        exercise: ExerciseType,
        imageAspect: Float
    ) -> SilhouetteCalibration? {
        if let size, size != (mask.width, mask.height) { reset() }
        if frames > 0, drift(from: anchorJoints, to: joints) > maximumJointDrift { reset() }
        if frames == 0 {
            size = (mask.width, mask.height)
            sum = Array(repeating: 0, count: mask.pixels.count)
            anchorJoints = joints
        }
        for index in sum.indices { sum[index] += mask.pixels[index] }
        for (joint, point) in joints {
            let current = jointSums[joint] ?? (0, 0, 0, 0)
            jointSums[joint] = (current.x + point.x, current.y + point.y, current.confidence + point.confidence, current.count + 1)
        }
        if let angle { angles.append(angle) }
        frames += 1
        guard frames >= requiredFrames, let size else { return nil }

        let count = Float(frames)
        let averaged = Self.largestRegion(of: GrayImage(width: size.width, height: size.height, pixels: sum.map { $0 / count }))
        // Keep joints seen in most frames; occasional detections are not reliable anchors.
        let averagedJoints = jointSums.reduce(into: [BodyJoint: JointPoint]()) { result, entry in
            let (joint, total) = entry
            guard total.count * 2 >= frames else { return }
            let n = Double(total.count)
            result[joint] = JointPoint(x: total.x / n, y: total.y / n, confidence: total.confidence / n)
        }
        let referenceAngle = angles.isEmpty ? nil : angles.sorted()[angles.count / 2]
        let scale = PoseCandidate(joints: averagedJoints)?.scale ?? 0
        reset()
        return SilhouetteCalibration(
            exercise: exercise,
            mask: averaged,
            joints: averagedJoints,
            referenceAngle: referenceAngle,
            bodyScale: scale,
            imageAspect: imageAspect
        )
    }

    /// Keeps the largest connected body region; lamps or posters the
    /// segmentation picked up would otherwise ride along with the trainee.
    static func largestRegion(of image: GrayImage, threshold: Float = 0.5) -> GrayImage {
        let width = image.width, height = image.height
        var component = [Int32](repeating: -1, count: width * height)
        var sizes: [Int] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where component[start] < 0 && image.pixels[start] > threshold {
            let id = Int32(sizes.count)
            var count = 0
            component[start] = id
            stack.append(start)
            while let index = stack.popLast() {
                count += 1
                let x = index % width, y = index / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let next = ny * width + nx
                    if component[next] < 0, image.pixels[next] > threshold {
                        component[next] = id
                        stack.append(next)
                    }
                }
            }
            sizes.append(count)
        }
        guard let largest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return image }
        // Keep the soft edge around the kept region by allowing pixels next to it.
        var pixels = image.pixels
        for index in pixels.indices where component[index] != Int32(largest) {
            let x = index % width, y = index / width
            var touches = false
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && nx < width && ny >= 0 && ny < height && component[ny * width + nx] == Int32(largest) {
                touches = true
            }
            if !touches || component[index] >= 0 { pixels[index] = 0 }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    private func drift(from anchor: [BodyJoint: JointPoint], to joints: [BodyJoint: JointPoint]) -> Double {
        let shared = anchor.keys.filter { joints[$0] != nil }
        guard !shared.isEmpty else { return .infinity }
        return shared.map { hypot(anchor[$0]!.x - joints[$0]!.x, anchor[$0]!.y - joints[$0]!.y) }.max() ?? 0
    }
}

/// Bones the outline is bound to. Each runs from a parent point to a child point.
enum RigBone: Int, CaseIterable, Sendable {
    case torso
    case head
    case leftUpperArm, leftForearm, rightUpperArm, rightForearm
    case leftThigh, leftShin, rightThigh, rightShin

    /// Bone whose motion a missing bone follows instead.
    var parent: RigBone? {
        switch self {
        case .torso: return nil
        case .head, .leftUpperArm, .rightUpperArm, .leftThigh, .rightThigh: return .torso
        case .leftForearm: return .leftUpperArm
        case .rightForearm: return .rightUpperArm
        case .leftShin: return .leftThigh
        case .rightShin: return .rightThigh
        }
    }

    func endpoints(in joints: [BodyJoint: JointPoint]) -> (SIMD2<Float>, SIMD2<Float>)? {
        func p(_ joint: BodyJoint) -> SIMD2<Float>? {
            joints[joint].map { SIMD2(Float($0.x), Float($0.y)) }
        }
        func mid(_ a: BodyJoint, _ b: BodyJoint) -> SIMD2<Float>? {
            switch (p(a), p(b)) {
            case let (a?, b?): return (a + b) / 2
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }
        let pair: (SIMD2<Float>?, SIMD2<Float>?)
        switch self {
        case .torso: pair = (p(.neck) ?? mid(.leftShoulder, .rightShoulder), mid(.leftHip, .rightHip))
        case .head: pair = (p(.neck) ?? mid(.leftShoulder, .rightShoulder), p(.nose))
        case .leftUpperArm: pair = (p(.leftShoulder), p(.leftElbow))
        case .leftForearm: pair = (p(.leftElbow), p(.leftWrist))
        case .rightUpperArm: pair = (p(.rightShoulder), p(.rightElbow))
        case .rightForearm: pair = (p(.rightElbow), p(.rightWrist))
        case .leftThigh: pair = (p(.leftHip), p(.leftKnee))
        case .leftShin: pair = (p(.leftKnee), p(.leftAnkle))
        case .rightThigh: pair = (p(.rightHip), p(.rightKnee))
        case .rightShin: pair = (p(.rightKnee), p(.rightAnkle))
        }
        guard let a = pair.0, let b = pair.1, simd_length_squared(b - a) > 1e-6 else { return nil }
        return (a, b)
    }
}

/// The calibration outline bound to a 2D skeleton, like a cut-out puppet.
/// Every outline pixel is assigned to its nearest bone, and each bone gets its
/// own grid mesh over just its pixels. A part follows its bone rigidly and
/// blends toward its parent only near the shared joint, so limbs that touched
/// the body during calibration separate cleanly instead of stretching.
///
/// Positions are in Vision's normalized space (origin bottom-left); texture
/// coordinates address `calibration.mask` and `partLabels` with row 0 at the top.
struct SkinnedSilhouette: Sendable {
    struct Influence: Equatable, Sendable {
        let first: RigBone
        let second: RigBone
        /// Weight of `first`; `second` gets the rest.
        let weight: Float
    }

    private struct Frame {
        let origin: SIMD2<Float>
        let along: SIMD2<Float>
        let across: SIMD2<Float>
        let length: Float
    }

    /// Marks pixels outside every part in `partLabels`.
    static let unlabeled: UInt8 = 255

    let calibration: SilhouetteCalibration
    /// Bone (`RigBone.rawValue`) owning each mask pixel, row 0 at the top.
    let partLabels: [UInt8]
    let restPositions: [SIMD2<Float>]
    let textureCoordinates: [SIMD2<Float>]
    /// Bone each vertex belongs to; the GPU draws only that bone's pixels.
    let vertexParts: [RigBone]
    let triangleIndices: [UInt32]
    let influences: [Influence]
    private let restFrames: [RigBone: Frame]
    private let aspect: Float

    static let maximumBoneStretch: Float = 1.6

    /// - Parameter cellSize: grid spacing in mask pixels.
    init?(calibration: SilhouetteCalibration, cellSize: Int = 5, coverageThreshold: Float = 0.02) {
        let mask = calibration.mask
        let aspect = calibration.imageAspect
        var frames: [RigBone: Frame] = [:]
        for bone in RigBone.allCases {
            if let (a, b) = bone.endpoints(in: calibration.joints) {
                frames[bone] = Self.frame(a, b, aspect: aspect)
            }
        }
        guard frames[.torso] != nil, mask.width > cellSize, mask.height > cellSize else { return nil }
        let bones = Array(frames.keys).sorted { $0.rawValue < $1.rawValue }

        // Label every pixel the soft edge reaches, so anti-aliasing survives.
        // Distance is measured to each bone's capsule, not its centre line, so a
        // thick torso keeps its sides when thin arms hang against it.
        let radii = Self.capsuleRadii(frames: frames, joints: calibration.joints, aspect: aspect)
        var labels = Array(repeating: Self.unlabeled, count: mask.pixels.count)
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask[x, y] > coverageThreshold {
                // Pixel centres, in the same edge-based coordinates as the mesh.
                let point = SIMD2((Float(x) + 0.5) / Float(mask.width) * aspect, 1 - (Float(y) + 0.5) / Float(mask.height))
                let nearest = bones.min {
                    Self.distance(point, to: frames[$0]!) - radii[$0, default: 0]
                        < Self.distance(point, to: frames[$1]!) - radii[$1, default: 0]
                }!
                labels[y * mask.width + x] = UInt8(nearest.rawValue)
            }
        }

        let step = max(2, cellSize)
        let columns = (mask.width - 1) / step + 1
        let rows = (mask.height - 1) / step + 1
        var positions: [SIMD2<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var parts: [RigBone] = []
        var indices: [UInt32] = []
        var influences: [Influence] = []
        for bone in bones {
            let label = UInt8(bone.rawValue)
            var touched = Array(repeating: false, count: columns * rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    var hit = false
                    var y = row * step
                    while !hit, y < min(mask.height, (row + 1) * step) {
                        var x = column * step
                        while x < min(mask.width, (column + 1) * step) {
                            if labels[y * mask.width + x] == label { hit = true; break }
                            x += 1
                        }
                        y += 1
                    }
                    touched[row * columns + column] = hit
                }
            }
            var vertexIndex = [Int: UInt32]()
            func vertex(_ gx: Int, _ gy: Int) -> UInt32 {
                let key = gy * (columns + 1) + gx
                if let existing = vertexIndex[key] { return existing }
                // Grid points sit on pixel edges, so a cell's quad covers exactly
                // the pixels whose labels put the cell in this part's mesh.
                let u = min(1, Float(gx * step) / Float(mask.width))
                let v = min(1, Float(gy * step) / Float(mask.height))
                let index = UInt32(positions.count)
                positions.append(SIMD2(u, 1 - v))
                uvs.append(SIMD2(u, v))
                parts.append(bone)
                influences.append(Self.influence(of: SIMD2(u * aspect, 1 - v), on: bone, frames: frames))
                vertexIndex[key] = index
                return index
            }
            for row in 0..<rows {
                for column in 0..<columns where touched[row * columns + column] {
                    let a = vertex(column, row), b = vertex(column + 1, row)
                    let c = vertex(column, row + 1), d = vertex(column + 1, row + 1)
                    indices += [a, b, c, b, d, c]
                }
            }
        }
        guard !indices.isEmpty else { return nil }

        self.calibration = calibration
        self.partLabels = labels
        self.restPositions = positions
        self.textureCoordinates = uvs
        self.vertexParts = parts
        self.triangleIndices = indices
        self.influences = influences
        self.restFrames = frames
        self.aspect = aspect
    }

    /// Typical half-thickness of each body part, relative to body proportions.
    private static func capsuleRadii(
        frames: [RigBone: Frame],
        joints: [BodyJoint: JointPoint],
        aspect: Float
    ) -> [RigBone: Float] {
        let torsoLength = frames[.torso]?.length ?? 0
        let shoulderWidth: Float = {
            guard let l = joints[.leftShoulder], let r = joints[.rightShoulder] else { return torsoLength * 0.6 }
            return simd_length(SIMD2(Float(l.x - r.x) * aspect, Float(l.y - r.y)))
        }()
        // Side-on, the shoulders overlap; the torso is still about a third as deep as it is long.
        let torso = max(shoulderWidth * 0.5, torsoLength * 0.3)
        return frames.reduce(into: [:]) { result, entry in
            let (bone, frame) = entry
            switch bone {
            case .torso: result[bone] = torso
            case .head: result[bone] = frame.length * 0.55
            case .leftUpperArm, .rightUpperArm: result[bone] = frame.length * 0.16
            case .leftForearm, .rightForearm: result[bone] = frame.length * 0.13
            case .leftThigh, .rightThigh: result[bone] = frame.length * 0.2
            case .leftShin, .rightShin: result[bone] = frame.length * 0.14
            }
        }
    }

    /// A part follows its own bone, blending toward its parent within the first
    /// part of its length so the joint bends instead of tearing.
    private static func influence(of point: SIMD2<Float>, on bone: RigBone, frames: [RigBone: Frame]) -> Influence {
        guard let parent = bone.parent, frames[parent] != nil, let own = frames[bone] else {
            return Influence(first: bone, second: bone, weight: 1)
        }
        let fromJoint = simd_length(point - own.origin)
        let reach = own.length * 0.45
        let blend = max(0, 1 - fromJoint / max(reach, 1e-6))
        return Influence(first: bone, second: parent, weight: 1 - 0.5 * blend * blend)
    }

    /// Vertex positions for the current pose, or `nil` when the torso is not visible.
    func deform(to joints: [BodyJoint: JointPoint]) -> [SIMD2<Float>]? {
        let transforms = boneTransforms(for: joints)
        guard transforms[.torso] != nil else { return nil }
        return restPositions.indices.map { index in
            let rest = SIMD2(restPositions[index].x * aspect, restPositions[index].y)
            let influence = influences[index]
            let a = apply(transforms, influence.first, to: rest)
            let b = apply(transforms, influence.second, to: rest)
            let blended = a * influence.weight + b * (1 - influence.weight)
            return SIMD2(blended.x / aspect, blended.y)
        }
    }

    /// 1 when every bone keeps its calibrated length, falling toward 0 as bones
    /// stretch or shrink (turning toward the camera) or go missing.
    func fit(to joints: [BodyJoint: JointPoint]) -> Double {
        var penalties: [Float] = []
        for (bone, rest) in restFrames {
            guard let (a, b) = bone.endpoints(in: joints) else {
                penalties.append(1)
                continue
            }
            let current = Self.frame(a, b, aspect: aspect)
            let ratio = current.length / max(rest.length, 1e-6)
            penalties.append(min(1, abs(log(ratio)) / log(Self.maximumBoneStretch)))
        }
        guard !penalties.isEmpty else { return 0 }
        return Double(1 - penalties.reduce(0, +) / Float(penalties.count))
    }

    private struct Transform {
        let rest: Frame
        let current: Frame
        let stretch: Float
    }

    private func boneTransforms(for joints: [BodyJoint: JointPoint]) -> [RigBone: Transform] {
        var result: [RigBone: Transform] = [:]
        for bone in RigBone.allCases {
            guard let rest = restFrames[bone], let (a, b) = bone.endpoints(in: joints) else { continue }
            let current = Self.frame(a, b, aspect: aspect)
            let stretch = min(Self.maximumBoneStretch, max(1 / Self.maximumBoneStretch, current.length / rest.length))
            result[bone] = Transform(rest: rest, current: current, stretch: stretch)
        }
        // A bone the camera lost follows its parent rigidly until it returns.
        for bone in RigBone.allCases where result[bone] == nil {
            var ancestor = bone.parent
            while let candidate = ancestor, result[candidate] == nil { ancestor = candidate.parent }
            if let ancestor, let parent = result[ancestor], let rest = restFrames[bone] {
                let moved = Frame(
                    origin: Self.map(rest.origin, parent),
                    along: Self.rotate(rest.along, parent),
                    across: Self.rotate(rest.across, parent),
                    length: rest.length
                )
                result[bone] = Transform(rest: rest, current: moved, stretch: 1)
            }
        }
        return result
    }

    private func apply(_ transforms: [RigBone: Transform], _ bone: RigBone, to point: SIMD2<Float>) -> SIMD2<Float> {
        guard let transform = transforms[bone] ?? transforms[.torso] else { return point }
        return Self.map(point, transform)
    }

    private static func map(_ point: SIMD2<Float>, _ transform: Transform) -> SIMD2<Float> {
        let local = point - transform.rest.origin
        let u = simd_dot(local, transform.rest.along) * transform.stretch
        let v = simd_dot(local, transform.rest.across)
        return transform.current.origin + transform.current.along * u + transform.current.across * v
    }

    private static func rotate(_ vector: SIMD2<Float>, _ transform: Transform) -> SIMD2<Float> {
        let u = simd_dot(vector, transform.rest.along)
        let v = simd_dot(vector, transform.rest.across)
        return transform.current.along * u + transform.current.across * v
    }

    private static func frame(_ a: SIMD2<Float>, _ b: SIMD2<Float>, aspect: Float) -> Frame {
        let start = SIMD2(a.x * aspect, a.y)
        let end = SIMD2(b.x * aspect, b.y)
        let length = max(simd_length(end - start), 1e-6)
        let along = (end - start) / length
        return Frame(origin: start, along: along, across: SIMD2(-along.y, along.x), length: length)
    }

    private static func distance(_ point: SIMD2<Float>, to frame: Frame) -> Float {
        let t = min(frame.length, max(0, simd_dot(point - frame.origin, frame.along)))
        return simd_length(point - (frame.origin + frame.along * t))
    }
}

/// How far into the current rep the trainee is, from their own calibrated top
/// (0) to the exercise's bottom angle (1).
enum RepDepthProgress {
    static func value(angle: Double?, referenceAngle: Double?, exercise: ExerciseType) -> Double? {
        guard let angle else { return nil }
        let configuration = exercise.repConfiguration
        let top = max(referenceAngle ?? configuration.topAngle, configuration.bottomAngle + 20)
        return min(1, max(0, (top - angle) / (top - configuration.bottomAngle)))
    }
}
