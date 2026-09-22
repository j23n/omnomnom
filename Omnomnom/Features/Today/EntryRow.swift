import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// Name, amount and energy for one entry, plus a badge when Health does not hold it fully
/// and an "Estimated" badge when the values came from the on-device model.
/// A recipe entry shows its servings next to the raw grams they weigh.
/// Every row reads as a button, with a chevron after the energy: a tap opens the
/// entry's editor. Every row also leads with a square: an entry with a photo, its own
/// or its recipe's or food's, shows it, and the thumbnail is a button of its own that
/// opens the photo, so the row's tap still works everywhere else. Without a photo the
/// square is the placeholder, which is decorative and has no tap of its own, so the
/// row opens the editor there like anywhere else.
struct EntryRow: View {
    let entry: LogEntry
    /// Opens the entry, for VoiceOver. The list handles the sighted tap, which cannot be
    /// a `Button` here because a row with a photo already holds one around its thumbnail.
    var onOpen: () -> Void = {}

    @State private var isShowingPhoto = false

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
            thumbnail
            summary
        }
    }

    /// The photo as a button that opens it full size, or the placeholder, which is only
    /// there to hold the row's left edge and carries no action of its own.
    @ViewBuilder
    private var thumbnail: some View {
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
        } else {
            PhotoThumbnail(data: nil, size: 44)
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
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the entry")
        .accessibilityAction { onOpen() }
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
