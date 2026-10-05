import DeveloperToolsSupport
import SwiftData
import SwiftUI

/// One meal slot's entries with delete and repeat swipe actions. Tapping any row hands its
/// entry to `onEdit`, which opens the editor; tapping the mark under a guessed food's name
/// hands it to `onQuestion` instead, which is why the row's own tap is a gesture rather than
/// a button — a button would swallow the one inside it. The header carries the slot's symbol
/// in the tint; the name keeps the list's own header styling and is what VoiceOver reads.
struct MealSection: View {
    let slot: MealSlot
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void
    let onRepeat: (LogEntry) -> Void
    let onEdit: (LogEntry) -> Void
    /// Asks about a match the app made rather than the user, from the mark on the row.
    var onQuestion: (LogEntry) -> Void = { _ in }

    var body: some View {
        Section {
            ForEach(entries) { entry in
                EntryRow(
                    entry: entry,
                    onOpen: { onEdit(entry) },
                    onQuestion: { onQuestion(entry) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onEdit(entry)
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
        } header: {
            Label {
                Text(slot.displayName)
            } icon: {
                Image(systemName: slot.symbolName)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
    }
}

#if DEBUG
#Preview("Health states", traits: .fixedLayout(width: 393, height: 700)) {
    let container = PreviewStore.container(seed: .healthStates)
    let entries = PreviewStore.entries(in: container)
    return List {
        ForEach(MealSlot.allCases, id: \.self) { slot in
            let slotEntries = entries.filter { $0.mealSlot == slot }
            if !slotEntries.isEmpty {
                MealSection(
                    slot: slot,
                    entries: slotEntries,
                    onDelete: { _ in },
                    onRepeat: { _ in },
                    onEdit: { _ in }
                )
            }
        }
    }
    .listStyle(.insetGrouped)
    .modelContainer(container)
}

#Preview("Typical day", traits: .fixedLayout(width: 393, height: 600)) {
    let container = PreviewStore.container(seed: .typicalDay)
    let entries = PreviewStore.entries(in: container)
    return List {
        ForEach(MealSlot.allCases, id: \.self) { slot in
            let slotEntries = entries.filter { $0.mealSlot == slot }
            if !slotEntries.isEmpty {
                MealSection(
                    slot: slot,
                    entries: slotEntries,
                    onDelete: { _ in },
                    onRepeat: { _ in },
                    onEdit: { _ in }
                )
            }
        }
    }
    .listStyle(.insetGrouped)
    .modelContainer(container)
}
#endif
