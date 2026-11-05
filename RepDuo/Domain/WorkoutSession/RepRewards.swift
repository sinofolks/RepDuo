import Foundation

/// How a single rep is celebrated, from the coach's 0–100 form score.
enum RepRating: Int, Equatable, Sendable, Comparable {
    case good
    case great
    case perfect

    init(score: Int?) {
        switch score ?? 0 {
        case 90...: self = .perfect
        case 75...: self = .great
        default: self = .good
        }
    }

    /// Points a rep adds toward the set's stars.
    var points: Double {
        switch self {
        case .perfect: return 1
        case .great: return 0.85
        case .good: return 0.7
        }
    }

    static func < (lhs: RepRating, rhs: RepRating) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The reward shown for one completed rep.
struct RepReward: Equatable, Sendable {
    let repNumber: Int
    let rating: RepRating
    /// Consecutive perfect reps including this one; 0 when this rep is not perfect.
    let combo: Int
    /// Every fifth rep, and the rep that first beats the personal best.
    let isGold: Bool
    let stars: Int
    /// True when this rep lit a new star.
    let earnedStar: Bool
}

/// Stars and streaks earned over a whole set.
public struct SetRewards: Equatable, Sendable {
    public let stars: Int
    public let bestCombo: Int
    public let perfectCount: Int
    public let goldCount: Int
}

/// Turns completed reps into ratings, combos, gold reps and up to five stars.
///
/// Stars fill against the set target: a perfect rep is worth a full point, so
/// five stars need the target reached with mostly perfect reps, while "good"
/// reps alone earn three at the target. Gold reps add a bonus on top.
struct RepRewardTracker {
    static let maximumStars = 5
    static let goldInterval = 5
    static let goldBonus = 0.5

    let target: Int
    let personalBest: Int
    private(set) var points: Double = 0
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var perfectCount = 0
    private(set) var goldCount = 0
    private(set) var lastReward: RepReward?

    init(target: Int, personalBest: Int = 0) {
        self.target = max(1, target)
        self.personalBest = max(0, personalBest)
    }

    /// 0...1 toward five stars.
    var progress: Double { min(1, points / Double(target)) }

    var stars: Int { Self.stars(for: progress) }

    var summary: SetRewards {
        SetRewards(stars: stars, bestCombo: bestCombo, perfectCount: perfectCount, goldCount: goldCount)
    }

    @discardableResult
    mutating func register(repNumber: Int, score: Int?) -> RepReward {
        let rating = RepRating(score: score)
        let previousStars = stars
        combo = rating == .perfect ? combo + 1 : 0
        bestCombo = max(bestCombo, combo)
        if rating == .perfect { perfectCount += 1 }
        let beatsBest = personalBest > 0 && repNumber == personalBest + 1
        let isGold = repNumber > 0 && (repNumber % Self.goldInterval == 0 || beatsBest)
        if isGold { goldCount += 1 }
        points += rating.points + (isGold ? Self.goldBonus : 0)
        let reward = RepReward(
            repNumber: repNumber,
            rating: rating,
            combo: combo,
            isGold: isGold,
            stars: stars,
            earnedStar: stars > previousStars
        )
        lastReward = reward
        return reward
    }

    static func stars(for progress: Double) -> Int {
        // A small epsilon so an exact 0.6 still lights the third star.
        min(maximumStars, Int((progress * Double(maximumStars) + 1e-9).rounded(.down)))
    }
}
