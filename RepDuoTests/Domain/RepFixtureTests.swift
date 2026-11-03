import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class RepFixtureTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let exercise: ExerciseType
        let expectedReps: Int
        let samples: [Sample]
    }

    private struct Sample: Decodable {
        let timestamp: Double
        let angle: Double?
        let quality: String?
        let formAcceptable: Bool?

        var poseQuality: PoseQuality {
            switch quality {
            case "usable": return .usable
            case "unstable": return .unstable
            case "missing": return .missingRequiredJoints
            case "multiple": return .multiplePeople
            default: return .excellent
            }
        }
    }

    func testRecordedNormalizedPoseFixtures() throws {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = .module
        #else
        bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(
            bundle.url(forResource: "rep_sequences", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "rep_sequences", withExtension: "json")
        )
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(fixtures.count, 9)

        for fixture in fixtures {
            let engine = RepDetectionEngine(exercise: fixture.exercise)
            fixture.samples.forEach { sample in
                _ = engine.process(PoseFrame(
                    timestamp: sample.timestamp,
                    quality: sample.poseQuality,
                    primaryAngle: sample.angle,
                    isFormAcceptable: sample.formAcceptable ?? true
                ))
            }
            XCTAssertEqual(engine.repCount, fixture.expectedReps, "Fixture failed: \(fixture.name)")
        }
    }
}
