import SwiftUI

/// One meal slot's entries with delete and repeat swipe actions.
struct MealSection: View {
    let slot: MealSlot
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void
    let onRepeat: (LogEntry) -> Void

    var body: some View {
        Section(slot.displayName) {
            ForEach(entries) { entry in
                EntryRow(entry: entry)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            onRepeat(entry)
                        } label: {
                            Label("Repeat", systemImage: "arrow.counterclockwise")
                        }
                        .tint(.accentColor)
                    }
            }
        }
    }
}
