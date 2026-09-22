import DeveloperToolsSupport
import Foundation
import SwiftUI

/// Name, amount and energy for one entry, plus a badge when Health does not hold it fully
/// and an "Estimated" badge when the values came from the on-device model.
/// A recipe entry shows its servings next to the raw grams they weigh.
/// Rows in the `partial` or `gone` state read as buttons: a tap opens the Health actions.
struct EntryRow: View {
    let entry: LogEntry

    private var isActionable: Bool { entry.healthState.needsAttention }

    private var hint: String {
        isActionable ? "Double tap to restore it to Health or remove it here" : ""
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                HStack(spacing: 6) {
                    if let servings = entry.servings {
                        Text("\(Formatters.servings(servings)) · \(Formatters.grams(entry.grams))")
                    } else {
                        Text(Formatters.grams(entry.grams))
                    }
                    Text(entry.timestamp, style: .time)
                    if entry.isEstimate {
                        EntryBadge(text: "Estimated")
                    }
                    if let badge = entry.healthState.badge {
                        EntryBadge(text: badge)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Formatters.amount(entry.snapshot.energy, unit: .kilocalorie))
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActionable ? .isButton : [])
        .accessibilityHint(hint)
    }
}

/// A small capsule caption next to the amount.
private struct EntryBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

#if DEBUG
#Preview("Health states", traits: .sizeThatFitsLayout) {
    // Synced, partial, gone, orphaned, unauthorized, an estimate and a product, in seed order.
    let container = PreviewStore.container(seed: .healthStates)
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.entries(in: container)) { entry in
            EntryRow(entry: entry)
        }
    }
    .padding()
    .modelContainer(container)
}

#Preview("Typical day with a recipe entry", traits: .sizeThatFitsLayout) {
    let container = PreviewStore.container(seed: .typicalDay)
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.entries(in: container)) { entry in
            EntryRow(entry: entry)
        }
    }
    .padding()
    .modelContainer(container)
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    let container = PreviewStore.container(seed: .healthStates)
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.entries(in: container)) { entry in
            EntryRow(entry: entry)
        }
    }
    .padding()
    .modelContainer(container)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
