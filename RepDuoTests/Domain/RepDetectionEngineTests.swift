import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class RepDetectionEngineTests: XCTestCase {
    func testSquatCountsOnlyAFullCycle() {
        let engine = RepDetectionEngine(exercise: .squat)
        let samples: [(Double, Double)] = [
            (0.0, 170), (0.1, 170),
            (0.2, 140), (0.3, 138),
            (0.5, 95), (0.6, 94),
            (0.7, 125), (0.8, 130),
            (1.0, 165), (1.1, 168)
        ]
        let updates = samples.map { engine.process(frame(at: $0.0, angle: $0.1)) }
        XCTAssertEqual(updates.last?.repCount, 1)
        XCTAssertEqual(updates.filter(\.completedRep).count, 1)
    }

    func testHalfSquatDoesNotCount() {
        let engine = RepDetectionEngine(exercise: .squat)
        let samples: [(Double, Double)] = [
            (0.0, 170), (0.1, 170),
            (0.3, 138), (0.4, 135),
            (0.8, 165), (0.9, 170)
        ]
        samples.forEach { _ = engine.process(frame(at: $0.0, angle: $0.1)) }
        XCTAssertEqual(engine.repCount, 0)
    }

    func testPushUpRejectsBrokenBodyLine() {
        let engine = RepDetectionEngine(exercise: .pushUp)
        let angles = [170.0, 170, 135, 130, 90, 90, 120, 125, 165, 170]
        for (index, angle) in angles.enumerated() {
            _ = engine.process(frame(at: Double(index) * 0.15, angle: angle, formAcceptable: false))
        }
        XCTAssertEqual(engine.repCount, 0)
    }

    func testMissingBodyFreezesState() {
        let engine = RepDetectionEngine(exercise: .squat)
        _ = engine.process(frame(at: 0, angle: 170))
        _ = engine.process(frame(at: 0.1, angle: 170))
        _ = engine.process(frame(at: 0.2, angle: 140))
        _ = engine.process(frame(at: 0.3, angle: 138))
        _ = engine.process(PoseFrame(timestamp: 0.4, quality: .missingRequiredJoints, primaryAngle: nil))
        _ = engine.process(PoseFrame(timestamp: 0.5, quality: .missingRequiredJoints, primaryAngle: nil))
        XCTAssertEqual(engine.repCount, 0)
    }

    func testPushUpCountsACompleteCycle() {
        let engine = RepDetectionEngine(exercise: .pushUp)
        run([170, 170, 138, 136, 94, 92, 120, 124, 166, 169], through: engine)
        XCTAssertEqual(engine.repCount, 1)
    }

    func testTooFastCycleDoesNotCount() {
        let engine = RepDetectionEngine(exercise: .squat)
        let angles = [170.0, 170, 140, 138, 95, 94, 125, 130, 165, 168]
        for (index, angle) in angles.enumerated() {
            _ = engine.process(frame(at: Double(index) * 0.04, angle: angle))
        }
        XCTAssertEqual(engine.repCount, 0)
    }

    func testStaleTimestampCannotAdvanceTheStateMachine() {
        let engine = RepDetectionEngine(exercise: .squat)
        _ = engine.process(frame(at: 1.0, angle: 170))
        _ = engine.process(frame(at: 1.1, angle: 170))
        for angle in [140.0, 95, 125, 168] {
            _ = engine.process(frame(at: 1.05, angle: angle))
        }
        XCTAssertEqual(engine.repCount, 0)
    }

    func testLongTrackingLossInvalidatesAPartialCycleButAllowsRecovery() {
        let engine = RepDetectionEngine(exercise: .squat)
        _ = engine.process(frame(at: 0, angle: 170))
        _ = engine.process(frame(at: 0.1, angle: 170))
        _ = engine.process(frame(at: 0.2, angle: 140))
        _ = engine.process(frame(at: 0.3, angle: 138))
        _ = engine.process(PoseFrame(timestamp: 0.4, quality: .missingRequiredJoints, primaryAngle: nil))
        _ = engine.process(PoseFrame(timestamp: 1.3, quality: .missingRequiredJoints, primaryAngle: nil))
        _ = engine.process(frame(at: 1.4, angle: 170))
        _ = engine.process(frame(at: 1.5, angle: 170))
        XCTAssertEqual(engine.repCount, 0)

        let recovery = [140.0, 138, 95, 94, 125, 130, 165, 168]
        for (index, angle) in recovery.enumerated() {
            _ = engine.process(frame(at: 1.7 + Double(index) * 0.15, angle: angle))
        }
        XCTAssertEqual(engine.repCount, 1)
    }

    func testShortOcclusionFreezesAndResumesTheSameCycle() {
        let engine = RepDetectionEngine(exercise: .squat)
        _ = engine.process(frame(at: 0, angle: 170))
        _ = engine.process(frame(at: 0.1, angle: 170))
        _ = engine.process(frame(at: 0.2, angle: 140))
        _ = engine.process(frame(at: 0.3, angle: 138))
        _ = engine.process(PoseFrame(timestamp: 0.4, quality: .unstable, primaryAngle: nil))
        let remaining = [95.0, 94, 125, 130, 165, 168]
        for (index, angle) in remaining.enumerated() {
            _ = engine.process(frame(at: 0.5 + Double(index) * 0.15, angle: angle))
        }
        XCTAssertEqual(engine.repCount, 1)
    }

    func testMultiplePeopleCannotAdvanceCounting() {
        let engine = RepDetectionEngine(exercise: .squat)
        for (index, angle) in [170.0, 170, 140, 138, 95, 94, 125, 130, 165, 168].enumerated() {
            _ = engine.process(frame(at: Double(index) * 0.15, angle: angle, quality: .multiplePeople))
        }
        XCTAssertEqual(engine.repCount, 0)
    }

    private func run(_ angles: [Double], through engine: RepDetectionEngine) {
        for (index, angle) in angles.enumerated() {
            _ = engine.process(frame(at: Double(index) * 0.15, angle: angle))
        }
    }

    private func frame(
        at time: Double,
        angle: Double,
        quality: PoseQuality = .excellent,
        formAcceptable: Bool = true
    ) -> PoseFrame {
        PoseFrame(
            timestamp: time,
            quality: quality,
            primaryAngle: angle,
            isFormAcceptable: formAcceptable
        )
    }
}
