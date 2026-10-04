import Foundation

/// One day on a chart: what was logged, and what the rolling mean was through it.
nonisolated struct TrendPoint: Identifiable, Hashable, Sendable {
    let day: Date
    /// The day's total, or `nil` when nothing was logged.
    ///
    /// `nil` and not zero. A zero-kilocalorie Tuesday is the one answer a nutrition
    /// chart must never give, and the difference between "ate nothing" and "recorded
    /// nothing" is the whole reason coverage exists.
    let value: Double?
    /// The seven-day mean through this day, or `nil` where the window is too sparse to
    /// mean anything.
    let mean: Double?
    let state: DayState

    var id: Date { day }
}

/// What a figure on the Trends screen rests on.
///
/// Carried beside every mean, because a mean over an unknown number of days is not a
/// fact about anyone's diet. Counts, never a share: see `DayState.note` for why a
/// proportion is the wrong shape here.
nonisolated struct TrendBasis: Hashable, Sendable {
    var complete = 0
    var partial = 0
    var assumed = 0
    var empty = 0

    var total: Int { complete + partial + assumed + empty }

    /// Whether a mean may be stated at all.
    var hasMean: Bool { complete > 0 }

    /// "67 complete days, 7 partial and 7 assumed", leaving out what is not there.
    ///
    /// Assumed days are named whenever there are any, because a day accepted in one tap
    /// is in the figures and the user should know how much of the line is theirs.
    var sentence: String {
        guard total > 0 else { return "Nothing logged in this range." }
        var parts: [String] = []
        // Left out when there are none, so "No complete days yet" is not followed by
        // "0 complete days".
        if complete > 0 { parts.append("\(complete) complete \(complete == 1 ? "day" : "days")") }
        if partial > 0 { parts.append("\(partial) partial") }
        if assumed > 0 { parts.append("\(assumed) assumed") }
        if empty > 0 { parts.append("\(empty) with nothing logged") }
        let list = TrendBasis.list(parts)
        return complete > 0 ? "Means cover \(list)." : "No complete days yet: \(list)."
    }

    /// "a, b and c" — an English list, since this is a sentence and not a table.
    static func list(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }
}

/// Turning daily totals into something an eye can follow.
///
/// Pure, so the two rules that decide whether the screen is honest are tested rather
/// than argued about: the mean breaks over a gap instead of bridging it, and it is only
/// ever stated alongside what it rests on.
nonisolated enum TrendMath {
    /// Days in the mean's window.
    static let window = 7

    /// How many of those days must hold data before a mean is drawn.
    ///
    /// Below this the window is describing a guess. Interpolating across a holiday would
    /// invent the one number nobody recorded, which is exactly the failure the whole
    /// coverage apparatus exists to prevent.
    static let minimumDays = 4

    /// Every day in the range, with its value, its state, and the mean through it.
    ///
    /// `days` is expected in ascending order and to be the complete set of dates in the
    /// range, gaps included, because a gap is a thing to draw rather than a thing to
    /// skip.
    static func series(
        days: [Date], values: [Date: Double], states: [Date: DayState]
    ) -> [TrendPoint] {
        days.enumerated().map { index, day in
            TrendPoint(
                day: day,
                value: values[day],
                mean: mean(endingAt: index, days: days, values: values),
                state: states[day] ?? (values[day] == nil ? .empty : .partial)
            )
        }
    }

    /// The trailing mean through one day, or `nil` when too few days in the window hold
    /// anything.
    static func mean(endingAt index: Int, days: [Date], values: [Date: Double]) -> Double? {
        let start = max(0, index - window + 1)
        let present = days[start...index].compactMap { values[$0] }
        guard present.count >= minimumDays else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    /// What the range holds, counted by state.
    static func basis(days: [Date], states: [Date: DayState], values: [Date: Double]) -> TrendBasis {
        var basis = TrendBasis()
        for day in days {
            switch states[day] ?? (values[day] == nil ? .empty : .partial) {
            case .complete: basis.complete += 1
            case .partial: basis.partial += 1
            case .assumed: basis.assumed += 1
            case .empty: basis.empty += 1
            }
        }
        return basis
    }

    /// The mean over complete days only, which is the figure a headline may state.
    ///
    /// Partial days are drawn but left out of this: a day holding breakfast alone would
    /// drag a mean down while looking like a light day, which is the one way the overview
    /// could mislead in the direction that matters.
    static func completeDayMean(
        days: [Date], values: [Date: Double], states: [Date: DayState]
    ) -> Double? {
        let present = days.compactMap { day -> Double? in
            guard states[day] == .complete else { return nil }
            return values[day]
        }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    /// Contiguous runs of days whose mean is defined.
    ///
    /// A chart draws one line per run. Handing the whole series to one line and hoping a
    /// missing value breaks it is how a line ends up drawn across a holiday, which is the
    /// app asserting a figure nobody recorded. Splitting it makes the break explicit and
    /// testable.
    static func segments(_ points: [TrendPoint]) -> [[TrendPoint]] {
        var runs: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        for point in points {
            if point.mean == nil {
                if !current.isEmpty { runs.append(current); current = [] }
            } else {
                current.append(point)
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Every day from `start` to `end` inclusive, so a gap is a date with no value
    /// rather than a missing row.
    static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
