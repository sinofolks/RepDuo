import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class RepRewardsTests: XCTestCase {
    func testRatingFollowsTheFormScore() {
        XCTAssertEqual(RepRating(score: 96), .perfect)
        XCTAssertEqual(RepRating(score: 90), .perfect)
        XCTAssertEqual(RepRating(score: 80), .great)
        XCTAssertEqual(RepRating(score: 60), .good)
        XCTAssertEqual(RepRating(score: nil), .good)
    }

    func testComboCountsConsecutivePerfectReps() {
        var tracker = RepRewardTracker(target: 10)
        XCTAssertEqual(tracker.register(repNumber: 1, score: 95).combo, 1)
        XCTAssertEqual(tracker.register(repNumber: 2, score: 92).combo, 2)
        XCTAssertEqual(tracker.register(repNumber: 3, score: 70).combo, 0)
        XCTAssertEqual(tracker.register(repNumber: 4, score: 99).combo, 1)
        XCTAssertEqual(tracker.summary.bestCombo, 2)
        XCTAssertEqual(tracker.summary.perfectCount, 3)
    }

    func testEveryFifthRepAndTheRecordRepAreGold() {
        var tracker = RepRewardTracker(target: 20, personalBest: 7)
        let gold = (1...10).filter { tracker.register(repNumber: $0, score: 80).isGold }
        XCTAssertEqual(gold, [5, 8, 10])
        XCTAssertEqual(tracker.summary.goldCount, 3)
    }

    func testFirstSetHasNoRecordRep() {
        var tracker = RepRewardTracker(target: 20, personalBest: 0)
        XCTAssertFalse(tracker.register(repNumber: 1, score: 80).isGold)
    }

    func testPerfectSetReachesFiveStars() {
        var tracker = RepRewardTracker(target: 10)
        var earned: [Int] = []
        for rep in 1...10 where tracker.register(repNumber: rep, score: 95).earnedStar {
            earned.append(rep)
        }
        XCTAssertEqual(tracker.stars, 5)
        XCTAssertEqual(earned.count, 5)
    }

    func testGoodRepsEarnFewerStarsThanPerfectOnes() {
        // Reps that skip every fifth number, so no gold bonus applies.
        var plain = RepRewardTracker(target: 10)
        for rep in [1, 2, 3, 4, 6, 7, 8, 9, 11, 12] { plain.register(repNumber: rep, score: 50) }
        XCTAssertEqual(plain.progress, 0.7, accuracy: 1e-9)
        XCTAssertEqual(plain.stars, 3)

        // Gold reps lift the same good-only effort to four stars: 20 × 0.7 + 4 × 0.5 = 16 of 20.
        var withGold = RepRewardTracker(target: 20)
        for rep in 1...20 { withGold.register(repNumber: rep, score: 50) }
        XCTAssertEqual(withGold.progress, 0.8, accuracy: 1e-9)
        XCTAssertEqual(withGold.stars, 4)
    }

    func testSessionPassesRewardsToStateAndSummary() {
        let session = WorkoutSession(exercise: .squat, setTarget: 3, monotonicStart: 0)
        session.registerDebugRep(at: 1)
        session.registerDebugRep(at: 2)
        session.registerDebugRep(at: 3)
        XCTAssertEqual(session.state.reward?.repNumber, 3)
        XCTAssertEqual(session.state.reward?.combo, 3)
        XCTAssertEqual(session.state.stars, 5)
        XCTAssertEqual(session.finish(monotonicTime: 4).rewards?.stars, 5)
    }
}
