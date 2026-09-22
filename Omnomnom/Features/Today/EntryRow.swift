import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// Name, amount and energy for one entry, plus a badge when Health does not hold it fully
/// and an "Estimated" badge when the values came from the on-device model.
/// A recipe entry shows its servings next to the raw grams they weigh.
/// Rows in the `partial` or `gone` state read as buttons, with a chevron after the
/// energy: a tap opens the Health actions.
struct EntryRow: View {
    let entry: LogEntry

    private var isActionable: Bool { entry.healthState.needsAttention }

    /// "1.5 servings · 351 g · 19:15": the amount, then the time it was logged.
    private var details: String {
        var parts: [String] = []
        if let servings = entry.servings {
            parts.append(Formatters.servings(servings))
        }
        parts.append(Formatters.wholeGrams(entry.grams))
        parts.append(entry.timestamp.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { caption }
                    VStack(alignment: .leading, spacing: 4) { caption }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ValueText(entry.snapshot.energy, unit: .kilocalorie)
            if isActionable {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActionable ? .isButton : [])
        .accessibilityHint(isActionable ? "Restore to Health or remove here" : "")
    }

    @ViewBuilder
    private var caption: some View {
        ValueText(details)
        if entry.isEstimate {
            Badge("Estimated")
        }
        if let text = entry.healthState.badgeText {
            Badge(text)
        }
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
