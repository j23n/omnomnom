import DeveloperToolsSupport
import SwiftData
import SwiftUI

/// One meal slot's entries with delete and repeat swipe actions. Tapping an entry that
/// Health no longer holds in full hands it to `onHealthAction`; other rows ignore taps.
/// The header carries the slot's symbol in the tint; the name keeps the list's own
/// header styling and is what VoiceOver reads.
struct MealSection: View {
    let slot: MealSlot
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void
    let onRepeat: (LogEntry) -> Void
    let onHealthAction: (LogEntry) -> Void

    var body: some View {
        Section {
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
                    onHealthAction: { _ in }
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
                    onHealthAction: { _ in }
                )
            }
        }
    }
    .listStyle(.insetGrouped)
    .modelContainer(container)
}
#endif
