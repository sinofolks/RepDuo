import XCTest
#if canImport(RepDuo)
@testable import RepDuo
#else
@testable import RepDuoCore
#endif

final class WorkoutStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()

    // Wednesday 2026-11-04 20:00 local time.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 20))!
    }

    private func set(_ exercise: ExerciseType, reps: Int, daysAgo: Int, hour: Int = 8) -> WorkoutSummary {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let start = calendar.date(byAdding: .hour, value: hour, to: day)!
        return WorkoutSummary(
            exercise: exercise,
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            repCount: reps,
            activeDuration: 60
        )
    }

    func testEmptyHistoryHasNoStreakOrBests() {
        let stats = WorkoutStats(summaries: [], now: now, calendar: calendar)
        XCTAssertEqual(stats.todayReps, 0)
        XCTAssertEqual(stats.streakDays, 0)
        XCTAssertEqual(stats.personalBest(for: .squat), 0)
        XCTAssertNil(stats.lastSet)
        XCTAssertEqual(stats.recentDailyReps.count, WorkoutStats.recentDayCount)
    }

    func testTodayAndWeekTotalsUseLocalCalendarWeek() {
        let stats = WorkoutStats(summaries: [
            set(.squat, reps: 20, daysAgo: 0),
            set(.pushUp, reps: 10, daysAgo: 0, hour: 18),
            set(.squat, reps: 15, daysAgo: 2),
            set(.squat, reps: 30, daysAgo: 3),
            set(.pushUp, reps: 12, daysAgo: 9)
        ], now: now, calendar: calendar)

        XCTAssertEqual(stats.todayReps, 30)
        XCTAssertEqual(stats.setsToday, 2)
        XCTAssertEqual(stats.todayIndex, 2)
        XCTAssertEqual(stats.currentWeekDailyReps, [15, 0, 30, 0, 0, 0, 0])
        XCTAssertEqual(stats.thisWeekReps, 45)
        XCTAssertEqual(stats.lastWeekReps, 30 + 12)
    }

    func testStreakSurvivesUntilTodayIsTrained() {
        let untrainedToday = WorkoutStats(summaries: [
            set(.squat, reps: 10, daysAgo: 1),
            set(.squat, reps: 10, daysAgo: 2),
            set(.squat, reps: 10, daysAgo: 4)
        ], now: now, calendar: calendar)
        XCTAssertFalse(untrainedToday.trainedToday)
        XCTAssertEqual(untrainedToday.streakDays, 2)

        let trainedToday = WorkoutStats(summaries: [
            set(.squat, reps: 10, daysAgo: 0),
            set(.squat, reps: 10, daysAgo: 1)
        ], now: now, calendar: calendar)
        XCTAssertEqual(trainedToday.streakDays, 2)

        let broken = WorkoutStats(summaries: [set(.squat, reps: 10, daysAgo: 2)], now: now, calendar: calendar)
        XCTAssertEqual(broken.streakDays, 0)
    }

    func testZeroRepSetsDoNotCountTowardStreaksOrBests() {
        let stats = WorkoutStats(summaries: [set(.squat, reps: 0, daysAgo: 0)], now: now, calendar: calendar)
        XCTAssertEqual(stats.streakDays, 0)
        XCTAssertEqual(stats.setsToday, 0)
        XCTAssertEqual(stats.personalBest(for: .squat), 0)
    }

    func testPersonalBestsAreTrackedPerExercise() {
        let stats = WorkoutStats(summaries: [
            set(.squat, reps: 32, daysAgo: 5),
            set(.squat, reps: 20, daysAgo: 1),
            set(.pushUp, reps: 26, daysAgo: 3)
        ], now: now, calendar: calendar)
        XCTAssertEqual(stats.personalBest(for: .squat), 32)
        XCTAssertEqual(stats.personalBest(for: .pushUp), 26)
        XCTAssertTrue(stats.isNewPersonalBest(set(.squat, reps: 33, daysAgo: 0)))
        XCTAssertFalse(stats.isNewPersonalBest(set(.squat, reps: 32, daysAgo: 0)))
        XCTAssertFalse(WorkoutStats(summaries: [], now: now, calendar: calendar)
            .isNewPersonalBest(set(.squat, reps: 5, daysAgo: 0)))
    }

    func testRecentDaysEndOnTodayAndLastSetIsNewest() {
        let newest = set(.pushUp, reps: 8, daysAgo: 0, hour: 19)
        let stats = WorkoutStats(summaries: [
            set(.squat, reps: 5, daysAgo: 27),
            set(.squat, reps: 9, daysAgo: 28),
            newest
        ], now: now, calendar: calendar)
        XCTAssertEqual(stats.recentDailyReps.first, 5)
        XCTAssertEqual(stats.recentDailyReps.last, 8)
        XCTAssertEqual(stats.lastSet, newest)
    }
}
