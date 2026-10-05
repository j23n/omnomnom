import Foundation
import Observation
import os
import SwiftData

/// One nutrient's series, ready to draw.
nonisolated struct NutrientTrend: Identifiable, Hashable, Sendable {
    let nutrient: Nutrient
    let points: [TrendPoint]
    /// The mean over complete days, or `nil` when there are none to average.
    let completeDayMean: Double?

    var id: Nutrient { nutrient }

    /// Whether anything at all was logged in the range.
    var hasData: Bool { points.contains { $0.value != nil } }
}

/// Loads what the Trends screen draws.
///
/// Two sources, split by what each is authoritative for. Health holds the totals,
/// because it counts every sample exactly once — this app's, other apps', and this app's
/// from another device — and survives a reinstall. The local store holds what a complete
/// day is, which Health has no idea about. Health is the numerator; the store is the
/// denominator and the honesty.
@Observable
final class TrendsModel {
    var range: TrendRange = .month
    private(set) var trends: [NutrientTrend] = []
    private(set) var coverage: [TrendPoint] = []
    private(set) var basis = TrendBasis()
    private(set) var isLoading = false
    /// Set when Health could not be read at all, which is different from it being empty.
    private(set) var note: String?

    private var task: Task<Void, Never>?

    /// Reloads for the current range. The newest load wins, so flipping the range twice
    /// quickly cannot leave the older answer on screen.
    func load(
        health: any HealthObserving, context: ModelContext, now: Date = .now,
        calendar: Calendar = .current
    ) {
        task?.cancel()
        isLoading = true
        let range = self.range
        task = Task { [weak self] in
            let end = calendar.startOfDay(for: now)
            let start = range.start(endingAt: end, calendar: calendar)
            let days = TrendMath.days(from: start, to: end, calendar: calendar)

            var totals: [Nutrient: [Date: Double]] = [:]
            var note: String?
            do {
                totals = try await health.dailyTotals(for: Nutrient.allCases, from: start, to: end)
            } catch {
                // An empty read is empty, never denied, so this is only ever a real
                // failure to reach the store rather than a permission problem.
                note = "Health could not be read just now."
                AppLog.health.error("trend read failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled, let self else { return }

            let states = Self.states(days: days, energy: totals[.energy] ?? [:], context: context, calendar: calendar)
            let energy = totals[.energy] ?? [:]
            self.trends = Nutrient.allCases.map { nutrient in
                let values = totals[nutrient] ?? [:]
                return NutrientTrend(
                    nutrient: nutrient,
                    points: TrendMath.series(days: days, values: values, states: states),
                    completeDayMean: TrendMath.completeDayMean(days: days, values: values, states: states)
                )
            }
            self.coverage = TrendMath.series(days: days, values: energy, states: states)
            self.basis = TrendMath.basis(days: days, states: states, values: energy)
            self.note = note
            self.isLoading = false
        }
    }

    /// What kind of day each date was, from the local store's records and the origins of
    /// its entries.
    ///
    /// Read on the main actor because it touches a `ModelContext`; the Health read above
    /// is what takes the time, and this is a handful of fetches over a bounded range.
    @MainActor
    private static func states(
        days: [Date], energy: [Date: Double], context: ModelContext, calendar: Calendar
    ) -> [Date: DayState] {
        guard let first = days.first, let last = days.last else { return [:] }
        let records = (try? DayRecord.records(from: first, to: last, in: context, calendar: calendar)) ?? [:]
        let origins = Self.origins(from: first, to: last, in: context, calendar: calendar)
        var states: [Date: DayState] = [:]
        for day in days {
            let dayOrigins = origins[day] ?? []
            // A day Health holds a figure for but this device has no entries on was
            // logged elsewhere; it counts as partial rather than empty, because there is
            // something there and this app did not put it there.
            let fallback: [EntryOrigin] = dayOrigins.isEmpty && energy[day] != nil ? [.picked] : dayOrigins
            states[day] = DayState.derive(
                entryOrigins: fallback,
                markedComplete: records[day]?.isComplete ?? false
            )
        }
        return states
    }

    /// Entry origins per day over the range, in one fetch.
    @MainActor
    private static func origins(
        from start: Date, to end: Date, in context: ModelContext, calendar: Calendar
    ) -> [Date: [EntryOrigin]] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.timestamp >= first && $0.timestamp < last }
        )
        guard let entries = try? context.fetch(descriptor) else { return [:] }
        return Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
            .mapValues { $0.map(\.origin) }
    }
}
