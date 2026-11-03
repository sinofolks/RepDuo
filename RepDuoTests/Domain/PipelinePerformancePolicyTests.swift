import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class PipelinePerformancePolicyTests: XCTestCase {
    func testNominalThermalPolicyPreservesBalancedRenderingAndFifteenHertzAnalysis() {
        let policy = PipelinePerformancePolicy.policy(for: .nominal)
        XCTAssertEqual(policy.rendererQuality, .balanced)
        XCTAssertEqual(policy.analysisStride, 2)
    }

    func testThermalPressureDegradesAnalysisAndGlowInSteps() {
        let fair = PipelinePerformancePolicy.policy(for: .fair)
        let serious = PipelinePerformancePolicy.policy(for: .serious)
        XCTAssertEqual(fair.rendererQuality, .lowPower)
        XCTAssertEqual(fair.analysisStride, 3)
        XCTAssertEqual(serious.rendererQuality, .thermalSafe)
        XCTAssertEqual(serious.analysisStride, 5)
    }

    func testMaskMayOnlyBeReusedInsideTheFreshnessWindow() {
        XCTAssertTrue(PipelineFramePolicy.canReuseMask(maskTimestamp: 1, forFrameAt: 1.28))
        XCTAssertFalse(PipelineFramePolicy.canReuseMask(maskTimestamp: 1, forFrameAt: 1.281))
    }

    func testMaskFromTheFutureOrInvalidTimestampIsRejected() {
        XCTAssertFalse(PipelineFramePolicy.canReuseMask(maskTimestamp: 2, forFrameAt: 1.9))
        XCTAssertFalse(PipelineFramePolicy.canReuseMask(maskTimestamp: .nan, forFrameAt: 2))
        XCTAssertFalse(PipelineFramePolicy.canReuseMask(maskTimestamp: nil, forFrameAt: 2))
    }
}
