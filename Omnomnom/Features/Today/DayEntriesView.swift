import Foundation
import os
import SwiftData
import SwiftUI

/// The entries of one day, queried live, with totals on top and swipe actions per row.
/// Local rows render first; what Health holds for the day is read afterwards and
/// folded into the totals and the "Also in Health" section.
struct DayEntriesView: View {
    let model: TodayViewModel
    private let interval: DateInterval

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.healthObserving) private var observing
    @Query private var entries: [LogEntry]
    @State private var healthSummary = DayHealthSummary.empty

    init(day: Date, model: TodayViewModel, calendar: Calendar = .current) {
        self.model = model
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        interval = DateInterval(start: start, end: end)
        _entries = Query(
            filter: #Predicate<LogEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \LogEntry.timestamp
        )
    }

    private var totals: Nutrition {
        SnapshotMath.total(of: entries.map(\.snapshot))
    }

    private var hasUnauthorizedEntries: Bool {
        entries.contains { $0.healthState == .unauthorized }
    }

    var body: some View {
        List {
            Section {
                TotalsRow(totals: totals, foreign: healthSummary.hasForeign ? healthSummary.foreign : nil)
            }
            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "fork.knife",
                        description: Text("Tap + to log one thing.")
                    )
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    let slotEntries = entries.filter { $0.mealSlot == slot }
                    if !slotEntries.isEmpty {
                        MealSection(
                            slot: slot,
                            entries: slotEntries,
                            onDelete: delete,
                            onRepeat: repeatEntry,
                            onHealthAction: { model.presentHealthActions(for: $0) }
                        )
                    }
                }
            }
            if !healthSummary.meals.isEmpty {
                ForeignMealsSection(meals: healthSummary.meals)
            }
        }
        .listStyle(.insetGrouped)
        .modifier(EntryHealthActions(model: model, onRestore: restore, onRemove: delete))
        .task(id: HealthReadKey(interval: interval, generation: model.healthRefresh)) {
            await loadHealthSummary()
        }
        .onChange(of: hasUnauthorizedEntries, initial: true) { _, hasAny in
            model.noteUnauthorizedEntries(hasAny)
        }
    }

    /// Reads the day from Health after the local rows are on screen; a failure leaves the
    /// previous summary in place and is logged inside the Health actor.
    private func loadHealthSummary() async {
        guard let samples = try? await observing.samples(in: interval) else { return }
        let summary = DayHealthSummary.make(from: samples, localEntryIDs: Set(entries.map(\.id)))
        healthSummary = summary
        AppLog.health.debug("day read: local \(totals.energy ?? 0) kcal, mirrored in Health \(summary.own.energy ?? 0) kcal, foreign \(summary.foreign.energy ?? 0) kcal")
    }

    private func delete(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.delete(entry, using: logger)
        }
    }

    private func restore(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.restore(entry, using: logger)
        }
    }

    private func repeatEntry(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.repeatEntry(entry, using: logger)
        }
    }
}

/// Identity of one Health read: the day window and a counter that forces a re-read.
private nonisolated struct HealthReadKey: Hashable, Sendable {
    let interval: DateInterval
    let generation: Int
}
