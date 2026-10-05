import Foundation
import Observation
import os
import SwiftData

/// One day of the run: what it answered, what it was made of, and whether it was asked
/// about at all.
nonisolated struct RunDay: Identifiable, Hashable, Sendable {
    let day: Date
    let answers: DayAnswers
    let composition: MacroComposition
    let state: DayState
    /// Whether the sampling cadence asks about this day. A day it does not ask about is
    /// drawn faintly and is not a miss.
    let isAsked: Bool

    var id: Date { day }
}

/// What the run screen reads: the run itself, and the month drawn under it.
///
/// Entirely local. The run counts days *this app* was told about, because that is what
/// answering means — a day logged in another app was not answered here, however much
/// energy Health holds for it. That is a deliberate difference from Shape, which reads
/// Health and says so.
@Observable
final class RunModel {
    private(set) var run = DayRun.empty
    /// The month being shown, oldest first, ending today.
    private(set) var month: [RunDay] = []
    private(set) var isLoaded = false

    /// How far back the run looks.
    ///
    /// Two years, so "your best" is a fact about this person rather than about the window,
    /// and bounded so the fetch behind it cannot grow without limit. Someone who has used
    /// the app for longer than that keeps a best from the last two years, which is the
    /// honest reading of a bounded window and is said on the screen.
    static let window = 730

    func load(
        context: ModelContext,
        cadence: SamplingCadence,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -Self.window, to: today) ?? today
        let days = TrendMath.days(from: start, to: today, calendar: calendar)
        let entries = Self.entries(from: start, in: context, calendar: calendar)
        let records = (try? DayRecord.records(from: start, to: today, in: context, calendar: calendar)) ?? [:]

        var states: [Date: DayState] = [:]
        for day in days {
            states[day] = DayState.derive(
                entryOrigins: (entries[day] ?? []).map(\.origin),
                markedComplete: records[day]?.isComplete ?? false
            )
        }
        run = DayRun.over(days: days, states: states, cadence: cadence, now: now, calendar: calendar)
        month = Self.monthToDate(endingAt: today, calendar: calendar).map { day in
            let onTheDay = entries[day] ?? []
            return RunDay(
                day: day,
                answers: DayAnswers(
                    entrySlots: onTheDay.map(\.mealSlot),
                    skipped: records[day]?.skippedSlots ?? []
                ),
                composition: MacroComposition(of: SnapshotMath.total(of: onTheDay.map(\.snapshot))),
                state: states[day] ?? .empty,
                isAsked: cadence.asks(about: day, calendar: calendar)
            )
        }
        isLoaded = true
    }

    /// The days of the month that have happened, oldest first.
    ///
    /// Nothing after today is drawn. A square for a day that has not come yet would be a
    /// day with nothing in it, which is exactly what a day someone missed looks like.
    static func monthToDate(endingAt today: Date, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.dateInterval(of: .month, for: today)?.start else { return [today] }
        return TrendMath.days(from: start, to: today, calendar: calendar)
    }

    /// The window's entries, grouped by day, in one fetch.
    private static func entries(
        from start: Date, in context: ModelContext, calendar: Calendar
    ) -> [Date: [LogEntry]] {
        let first = calendar.startOfDay(for: start)
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.timestamp >= first }
        )
        guard let entries = try? context.fetch(descriptor) else {
            AppLog.store.error("run read failed")
            return [:]
        }
        return Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
    }
}
