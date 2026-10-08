import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// Name, amount and energy for one entry, plus a badge when Health does not hold it fully
/// and an "Estimated" badge when the values came from the on-device model.
/// A recipe entry shows its servings next to the raw amount they come to.
/// Every row reads as a button, with a chevron after the energy: a tap opens the
/// entry's editor. Every row also leads with a square: an entry with a photo, its own
/// or its recipe's or food's, shows it, and the thumbnail is a button of its own that
/// opens the photo, so the row's tap still works everywhere else. Without a photo the
/// square is the placeholder, which is decorative and has no tap of its own, so the
/// row opens the editor there like anywhere else.
///
/// A row whose food the app chose rather than the user carries the mark: the name is
/// underlined, as a word a spellchecker is unsure of is underlined, and under it sits what
/// the line called it. Both say the same thing — this is logged, and it is the app's reading
/// of your words rather than your own. The mark is a button, and answering it is what takes
/// it off. Nothing about it is red, bordered or badged: it asks a question, it does not
/// report a fault, and there is nothing wrong with the entry.
struct EntryRow: View {
    let entry: LogEntry
    /// Opens the entry, for VoiceOver. The list handles the sighted tap, which cannot be
    /// a `Button` here because a row with a photo already holds one around its thumbnail.
    var onOpen: () -> Void = {}
    /// Asks about a match the app made rather than the user. Reached from the mark under
    /// the name, which is a button of its own inside the row as the thumbnail is.
    var onQuestion: () -> Void = {}

    @State private var isShowingPhoto = false

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
                    .underline(entry.guessed, pattern: .dot)
                if entry.guessed {
                    mark
                }
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
        // The mark's own button is inside a combined element, so its words are read as
        // part of the row and its tap has to come back as a named action.
        .accessibilityActions {
            if entry.guessed {
                Button("Check the match") { onQuestion() }
            }
        }
    }

    /// The mark: what the line called this food, and a way to say whether the app read it
    /// right. Secondary type, no colour of its own, and the chevron is what says it leads
    /// somewhere.
    private var mark: some View {
        Button(action: onQuestion) {
            HStack(spacing: 4) {
                Text(Self.markText(for: entry))
                Image(systemName: "chevron.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// "Matched from “oats”", or what it has to say when nothing was said: a line logged
    /// from a widget tap or a photo carries no words of its own.
    static func markText(for entry: LogEntry) -> String {
        guard let wording = entry.wording, !wording.isEmpty else { return "Matched for you" }
        return "Matched from “\(wording)”"
    }

    /// "Today, 08:10": the day as Today names it, then the time.
    private static func photoSubtitle(for timestamp: Date) -> String {
        "\(Formatters.dayTitle(timestamp)), \(timestamp.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var caption: some View {
        // The same line the match sheet asks its question against, so the row and the
        // question can never disagree about what was logged.
        ValueText(GuessedMatchSheet.loggedDetail(of: entry))
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

#Preview("The mark", traits: .sizeThatFitsLayout) {
    // Three rows in one: a word the app read, a line that carried no words of its own,
    // and an unmarked row to see the first two against.
    let container = PreviewStore.container(seed: .typicalDay)
    let entries = PreviewStore.entries(in: container)
    if let first = entries.first {
        first.wording = "oats"
        first.guessed = true
    }
    if entries.count > 1 {
        entries[1].guessed = true
    }
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(entries.prefix(3)) { entry in
            EntryRow(entry: entry)
        }
    }
    .padding()
    .modelContainer(container)
}

#Preview("The mark at accessibility 5", traits: .sizeThatFitsLayout) {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first
    entry?.wording = "a bowl of porridge with some honey"
    entry?.guessed = true
    return VStack(alignment: .leading, spacing: 16) {
        if let entry {
            EntryRow(entry: entry)
        }
    }
    .padding()
    .modelContainer(container)
    .environment(\.dynamicTypeSize, .accessibility5)
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
