import XCTest
import simd
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class SkinnedSilhouetteTests: XCTestCase {
    private let size = (width: 90, height: 160)

    func testCalibratorAveragesStillFrames() {
        let calibrator = SilhouetteCalibrator(requiredFrames: 3)
        let joints = standingJoints()
        let mask = paint(joints)

        XCTAssertNil(calibrator.add(mask: mask, joints: joints, angle: 170, exercise: .squat, imageAspect: Float(aspect)))
        XCTAssertNil(calibrator.add(mask: mask, joints: joints, angle: 172, exercise: .squat, imageAspect: Float(aspect)))
        let calibration = calibrator.add(mask: mask, joints: joints, angle: 168, exercise: .squat, imageAspect: Float(aspect))

        XCTAssertEqual(calibration?.mask, mask)
        XCTAssertEqual(calibration?.referenceAngle, 170)
        XCTAssertEqual(calibration?.joints.count, joints.count)
        XCTAssertGreaterThan(calibration?.bodyScale ?? 0, 0.1)
    }

    func testCalibratorRestartsWhenTheTraineeMoves() {
        let calibrator = SilhouetteCalibrator(requiredFrames: 2, maximumJointDrift: 0.02)
        let joints = standingJoints()
        let moved = joints.mapValues { JointPoint(x: $0.x + 0.1, y: $0.y, confidence: $0.confidence) }

        XCTAssertNil(calibrator.add(mask: paint(joints), joints: joints, angle: nil, exercise: .squat, imageAspect: Float(aspect)))
        XCTAssertNil(calibrator.add(mask: paint(moved), joints: moved, angle: nil, exercise: .squat, imageAspect: Float(aspect)))
        XCTAssertEqual(calibrator.progress, 0.5, accuracy: 0.001)
        XCTAssertNotNil(calibrator.add(mask: paint(moved), joints: moved, angle: nil, exercise: .squat, imageAspect: Float(aspect)))
    }

    func testCalibrationDropsDetachedBlobs() {
        var pixels = paint(standingJoints()).pixels
        // A lamp in the corner, well away from the body.
        for y in 2..<8 { for x in 2..<8 { pixels[y * size.width + x] = 1 } }
        let cleaned = SilhouetteCalibrator.largestRegion(of: GrayImage(width: size.width, height: size.height, pixels: pixels))
        XCTAssertEqual(cleaned[4, 4], 0)
        XCTAssertEqual(cleaned[45, 80], 1)
    }

    func testRestPoseLeavesTheMeshInPlace() throws {
        let silhouette = try makeSilhouette()
        let deformed = try XCTUnwrap(silhouette.deform(to: standingJoints()))

        for (rest, current) in zip(silhouette.restPositions, deformed) {
            XCTAssertEqual(rest.x, current.x, accuracy: 1e-4)
            XCTAssertEqual(rest.y, current.y, accuracy: 1e-4)
        }
        XCTAssertEqual(silhouette.fit(to: standingJoints()), 1, accuracy: 1e-6)
        XCTAssertEqual(silhouette.triangleIndices.count % 3, 0)
        XCTAssertEqual(silhouette.textureCoordinates.count, silhouette.restPositions.count)
    }

    func testFootFollowsABentKnee() throws {
        let silhouette = try makeSilhouette()
        var bent = standingJoints()
        // Swing the left shin 90° forward around the knee, keeping its length.
        let knee = bent[.leftKnee]!, ankle = bent[.leftAnkle]!
        let shinLength = hypot((ankle.x - knee.x) * aspect, ankle.y - knee.y)
        bent[.leftAnkle] = JointPoint(x: knee.x + shinLength / aspect, y: knee.y, confidence: 0.9)

        let deformed = try XCTUnwrap(silhouette.deform(to: bent))
        let restAnkle = SIMD2(Float(ankle.x), Float(ankle.y))
        let nearest = silhouette.restPositions.indices.min {
            simd_distance(silhouette.restPositions[$0], restAnkle) < simd_distance(silhouette.restPositions[$1], restAnkle)
        }!
        let moved = deformed[nearest]
        XCTAssertEqual(Double(moved.x), bent[.leftAnkle]!.x, accuracy: 0.05)
        XCTAssertEqual(Double(moved.y), knee.y, accuracy: 0.05)
        // The torso does not move.
        let neck = SIMD2(Float(bent[.neck]!.x), Float(bent[.neck]!.y))
        let torsoVertex = silhouette.restPositions.indices.min {
            simd_distance(silhouette.restPositions[$0], neck) < simd_distance(silhouette.restPositions[$1], neck)
        }!
        XCTAssertEqual(simd_distance(deformed[torsoVertex], silhouette.restPositions[torsoVertex]), 0, accuracy: 1e-3)
    }

    func testMissingForearmFollowsUpperArm() throws {
        let silhouette = try makeSilhouette()
        var joints = standingJoints()
        joints[.leftWrist] = nil
        XCTAssertNotNil(silhouette.deform(to: joints))
        XCTAssertLessThan(silhouette.fit(to: joints), 1)
    }

    func testFitDropsWhenBonesForeshorten() throws {
        let silhouette = try makeSilhouette()
        var joints = standingJoints()
        // Thighs pointing at the camera look much shorter.
        for (hip, knee) in [(BodyJoint.leftHip, BodyJoint.leftKnee), (.rightHip, .rightKnee)] {
            let h = joints[hip]!, k = joints[knee]!
            joints[knee] = JointPoint(x: k.x, y: h.y - (h.y - k.y) * 0.4, confidence: 0.9)
        }
        XCTAssertLessThan(silhouette.fit(to: joints), 0.85)
    }

    func testDepthProgressUsesTheCalibratedTop() {
        XCTAssertEqual(RepDepthProgress.value(angle: 170, referenceAngle: 170, exercise: .squat), 0)
        XCTAssertEqual(RepDepthProgress.value(angle: 105, referenceAngle: 170, exercise: .squat), 1)
        XCTAssertEqual(RepDepthProgress.value(angle: 137.5, referenceAngle: 170, exercise: .squat)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(RepDepthProgress.value(angle: 80, referenceAngle: nil, exercise: .pushUp), 1)
        XCTAssertNil(RepDepthProgress.value(angle: nil, referenceAngle: 170, exercise: .squat))
    }

    // MARK: Fixtures

    private var aspect: Double { Double(size.width) / Double(size.height) }

    private func makeSilhouette() throws -> SkinnedSilhouette {
        let joints = standingJoints()
        let calibration = SilhouetteCalibration(
            exercise: .squat,
            mask: paint(joints),
            joints: joints,
            referenceAngle: 170,
            bodyScale: 0.4,
            imageAspect: Float(aspect)
        )
        return try XCTUnwrap(SkinnedSilhouette(calibration: calibration, cellSize: 4))
    }

    private func standingJoints() -> [BodyJoint: JointPoint] {
        func j(_ x: Double, _ y: Double) -> JointPoint { JointPoint(x: x, y: y, confidence: 0.9) }
        return [
            .nose: j(0.5, 0.88), .neck: j(0.5, 0.80),
            .leftShoulder: j(0.42, 0.78), .rightShoulder: j(0.58, 0.78),
            .leftElbow: j(0.38, 0.64), .rightElbow: j(0.62, 0.64),
            .leftWrist: j(0.37, 0.52), .rightWrist: j(0.63, 0.52),
            .leftHip: j(0.45, 0.52), .rightHip: j(0.55, 0.52),
            .leftKnee: j(0.45, 0.32), .rightKnee: j(0.55, 0.32),
            .leftAnkle: j(0.45, 0.12), .rightAnkle: j(0.55, 0.12)
        ]
    }

    /// Paints thick limbs between joints, the way a segmentation mask would look.
    private func paint(_ joints: [BodyJoint: JointPoint]) -> GrayImage {
        var pixels = Array(repeating: Float(0), count: size.width * size.height)
        let segments: [(BodyJoint, BodyJoint)] = [
            (.neck, .leftHip), (.neck, .rightHip), (.neck, .nose),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]
        for y in 0..<size.height {
            for x in 0..<size.width {
                let p = SIMD2(Double(x) / Double(size.width - 1) * aspect, 1 - Double(y) / Double(size.height - 1))
                for (a, b) in segments {
                    guard let ja = joints[a], let jb = joints[b] else { continue }
                    let s = SIMD2(ja.x * aspect, ja.y), e = SIMD2(jb.x * aspect, jb.y)
                    let t = max(0, min(1, simd_dot(p - s, e - s) / max(simd_length_squared(e - s), 1e-9)))
                    if simd_distance(p, s + (e - s) * t) < 0.035 { pixels[y * size.width + x] = 1; break }
                }
            }
        }
        return GrayImage(width: size.width, height: size.height, pixels: pixels)
    }
}
