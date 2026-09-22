import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// Name, amount and energy for one entry, plus a badge when Health does not hold it fully
/// and an "Estimated" badge when the values came from the on-device model.
/// A recipe entry shows its servings next to the raw grams they weigh.
/// Rows in the `partial` or `gone` state read as buttons, with a chevron after the
/// energy: a tap opens the Health actions. An entry with a photo, its own or its
/// recipe's or food's, leads with a thumbnail that opens the photo; the thumbnail is
/// a button of its own, so the row's tap still works everywhere else.
struct EntryRow: View {
    let entry: LogEntry

    @State private var isShowingPhoto = false

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
        HStack(spacing: 12) {
            if let photo = entry.displayPhoto?.data {
                Button {
                    isShowingPhoto = true
                } label: {
                    PhotoThumbnail(data: photo, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo")
                .sheet(isPresented: $isShowingPhoto) {
                    PhotoViewer(data: photo, title: entry.foodName, subtitle: Self.photoSubtitle(for: entry.timestamp))
                }
            }
            summary
        }
    }

    /// Everything but the thumbnail, combined into one element for VoiceOver.
    private var summary: some View {
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

    /// "Today, 08:10": the day as Today names it, then the time.
    private static func photoSubtitle(for timestamp: Date) -> String {
        "\(Formatters.dayTitle(timestamp)), \(timestamp.formatted(date: .omitted, time: .shortened))"
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

#Preview("Typical day with photos", traits: .sizeThatFitsLayout) {
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
