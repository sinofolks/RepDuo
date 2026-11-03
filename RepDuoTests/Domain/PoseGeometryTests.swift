import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class PoseGeometryTests: XCTestCase {
    func testRightAngle() {
        let first = JointPoint(x: 1, y: 0, confidence: 1)
        let vertex = JointPoint(x: 0, y: 0, confidence: 1)
        let third = JointPoint(x: 0, y: 1, confidence: 1)
        XCTAssertEqual(PoseGeometry.angle(first, vertex: vertex, third), 90, accuracy: 0.001)
    }

    func testStraightAngle() {
        let first = JointPoint(x: -1, y: 0, confidence: 1)
        let vertex = JointPoint(x: 0, y: 0, confidence: 1)
        let third = JointPoint(x: 1, y: 0, confidence: 1)
        XCTAssertEqual(PoseGeometry.angle(first, vertex: vertex, third), 180, accuracy: 0.001)
    }

    func testDistanceFromLine() {
        let point = JointPoint(x: 0.5, y: 0.25, confidence: 1)
        let start = JointPoint(x: 0, y: 0, confidence: 1)
        let end = JointPoint(x: 1, y: 0, confidence: 1)
        XCTAssertEqual(PoseGeometry.distanceFromLine(point, lineStart: start, lineEnd: end), 0.25, accuracy: 0.001)
    }

    func testAspectFillCoordinateTransformCentersTheImage() {
        let center = JointPoint(x: 0.5, y: 0.5, confidence: 0.9)
        let mapped = PoseCoordinateTransform.aspectFill(
            center,
            imageWidth: 1280,
            imageHeight: 720,
            viewportWidth: 390,
            viewportHeight: 844,
            mirrored: false
        )
        XCTAssertEqual(mapped.x, 195, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 422, accuracy: 0.001)
        XCTAssertEqual(mapped.confidence, 0.9)
    }

    func testMirroringFlipsTheHorizontalCoordinateAfterAspectFillCrop() {
        let point = JointPoint(x: 0.25, y: 0.5, confidence: 1)
        let normal = PoseCoordinateTransform.aspectFill(
            point,
            imageWidth: 1280,
            imageHeight: 720,
            viewportWidth: 390,
            viewportHeight: 844,
            mirrored: false
        )
        let mirrored = PoseCoordinateTransform.aspectFill(
            point,
            imageWidth: 1280,
            imageHeight: 720,
            viewportWidth: 390,
            viewportHeight: 844,
            mirrored: true
        )
        XCTAssertEqual(normal.x + mirrored.x, 390, accuracy: 0.001)
    }
}
