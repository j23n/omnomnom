import Foundation
import SwiftData
import SwiftUI

/// The entries of one day, queried live, with totals on top and swipe actions per row.
struct DayEntriesView: View {
    let model: TodayViewModel

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Query private var entries: [LogEntry]

    init(day: Date, model: TodayViewModel, calendar: Calendar = .current) {
        self.model = model
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<LogEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \LogEntry.timestamp
        )
    }

    private var totals: Nutrition {
        SnapshotMath.total(of: entries.map(\.snapshot))
    }

    var body: some View {
        List {
            Section {
                TotalsRow(totals: totals)
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
                        MealSection(slot: slot, entries: slotEntries, onDelete: delete, onRepeat: repeatEntry)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func delete(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.delete(entry, using: logger)
        }
    }

    private func repeatEntry(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.repeatEntry(entry, using: logger)
        }
    }
}
