import Foundation

/// Training totals derived from saved set summaries for the home, history,
/// and share surfaces. Days follow the supplied calendar, so streaks and
/// weekly totals roll over at local midnight.
struct WorkoutStats: Equatable, Sendable {
    let todayReps: Int
    let thisWeekReps: Int
    let lastWeekReps: Int
    /// Reps per day for the current calendar week, starting on the calendar's first weekday.
    let currentWeekDailyReps: [Int]
    /// Position of today inside `currentWeekDailyReps`.
    let todayIndex: Int
    /// Consecutive training days ending today, or ending yesterday when today has no reps yet.
    let streakDays: Int
    let trainedToday: Bool
    let setsToday: Int
    let personalBests: [ExerciseType: Int]
    let lastSet: WorkoutSummary?
    /// Reps per day for the trailing 28 days, oldest first, ending today.
    let recentDailyReps: [Int]

    static let recentDayCount = 28

    init(summaries: [WorkoutSummary], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        var repsByDay: [Date: Int] = [:]
        var bests: [ExerciseType: Int] = [:]
        var setsToday = 0
        for summary in summaries where summary.repCount > 0 {
            let day = calendar.startOfDay(for: summary.startedAt)
            repsByDay[day, default: 0] += summary.repCount
            bests[summary.exercise] = max(bests[summary.exercise] ?? 0, summary.repCount)
            if day == today { setsToday += 1 }
        }

        func day(_ offset: Int, from start: Date) -> Date {
            calendar.date(byAdding: .day, value: offset, to: start) ?? start
        }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let lastWeekStart = day(-7, from: weekStart)
        currentWeekDailyReps = (0..<7).map { repsByDay[day($0, from: weekStart)] ?? 0 }
        todayIndex = max(0, min(6, calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0))
        thisWeekReps = currentWeekDailyReps.reduce(0, +)
        lastWeekReps = (0..<7).reduce(0) { $0 + (repsByDay[day($1, from: lastWeekStart)] ?? 0) }

        todayReps = repsByDay[today] ?? 0
        trainedToday = todayReps > 0
        self.setsToday = setsToday
        var streak = 0
        var cursor = trainedToday ? today : day(-1, from: today)
        while (repsByDay[cursor] ?? 0) > 0 {
            streak += 1
            cursor = day(-1, from: cursor)
        }
        streakDays = streak

        recentDailyReps = (0..<Self.recentDayCount).map {
            repsByDay[day($0 - Self.recentDayCount + 1, from: today)] ?? 0
        }
        personalBests = bests
        lastSet = summaries.max { $0.startedAt < $1.startedAt }
    }

    func personalBest(for exercise: ExerciseType) -> Int {
        personalBests[exercise] ?? 0
    }

    /// A finished set is a record only when it beats an existing best; a first
    /// ever set establishes the best without being celebrated as a record.
    func isNewPersonalBest(_ summary: WorkoutSummary) -> Bool {
        let previous = personalBest(for: summary.exercise)
        return previous > 0 && summary.repCount > previous
    }
}
