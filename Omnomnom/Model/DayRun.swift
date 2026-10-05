import Foundation

/// How many days in a row were answered, and the longest run there has been.
///
/// It counts days *answered*, never days eaten well, and a skipped meal is an answer — so
/// what it rewards is closing the day rather than eating in any particular way. Three
/// rules keep it from punishing the thing the rest of the app calls normal:
///
/// - Days the sampling cadence does not ask about are stepped over, not failed.
/// - A day still open neither extends the run nor breaks it, so today is never a loss.
/// - A gap ends the current run and never touches `best`, which stays on screen beside it.
///
/// Derived, never stored. Every input already exists: `DayState` per day, and the cadence.
nonisolated struct DayRun: Hashable, Sendable {
    /// Consecutive answered days ending at the most recent settled day.
    let current: Int
    /// The longest run of answered days among the settled days considered.
    let best: Int
    /// A day that is unanswered, still inside the grace window and no longer today.
    ///
    /// The one worth a prompt: today being unanswered is just the day not being over.
    let open: Date?

    /// Nothing counted.
    static let empty = DayRun(current: 0, best: 0, open: nil)

    /// How long a past day stays answerable before it counts against the run.
    ///
    /// One day, so a meal remembered the next morning is a save rather than a loss. It is
    /// a single value because it is a tuning decision, not a fact.
    static let graceDays = 1

    /// The run over `days`, which must be the window to consider and need not be sorted.
    ///
    /// A day with no entry in `states` is treated as `.empty`, which is what a day the
    /// store has never heard of is.
    static func over(
        days: some Sequence<Date>,
        states: [Date: DayState],
        cadence: SamplingCadence,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayRun {
        let today = calendar.startOfDay(for: now)
        let graceStart = calendar.date(byAdding: .day, value: -graceDays, to: today) ?? today

        // Only the days the cadence asks about, and never one that has not happened.
        let asked = Set(days.map { calendar.startOfDay(for: $0) })
            .filter { $0 <= today && cadence.asks(about: $0, calendar: calendar) }
            .sorted()
        guard !asked.isEmpty else { return .empty }

        func isAnswered(_ day: Date) -> Bool { (states[day] ?? .empty).isAnswered }
        /// Still answerable, so it is neither a link in the run nor a break in it.
        func isStillOpen(_ day: Date) -> Bool { !isAnswered(day) && day >= graceStart }

        // The run reads backwards from the most recent day that has settled either way.
        var current = 0
        var sawSettled = false
        for day in asked.reversed() {
            if !sawSettled, isStillOpen(day) { continue }
            sawSettled = true
            guard isAnswered(day) else { break }
            current += 1
        }

        // The best run only ever looks at settled days, and open ones are only ever at the
        // end, so walking the lot and stopping the tally on an open day is enough.
        var best = 0
        var run = 0
        for day in asked {
            if isStillOpen(day) { break }
            run = isAnswered(day) ? run + 1 : 0
            best = max(best, run)
        }

        let open = asked.last { $0 != today && isStillOpen($0) }
        return DayRun(current: current, best: max(best, current), open: open)
    }
}
