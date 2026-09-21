import SwiftUI

/// One meal slot's entries with delete and repeat swipe actions. Tapping an entry that
/// Health no longer holds in full hands it to `onHealthAction`; other rows ignore taps.
struct MealSection: View {
    let slot: MealSlot
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void
    let onRepeat: (LogEntry) -> Void
    let onHealthAction: (LogEntry) -> Void

    var body: some View {
        Section(slot.displayName) {
            ForEach(entries) { entry in
                EntryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if entry.healthState.needsAttention {
                            onHealthAction(entry)
                        }
                    }
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
