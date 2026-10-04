import SwiftUI

/// A meal this person usually eats, offered rather than assumed.
///
/// Visibly not logged: a dashed edge, the word "usually", and a button that has to be
/// pressed. Nothing has reached Health and no entry exists in the store until it is.
///
/// The footnote states both halves of the bargain *before* the tap and not after: these
/// figures go to Health, and the day counts as assumed rather than complete. One tap is
/// cheap enough that it stops being much of an assertion, so the day it produces is
/// marked as what it is and a mean that includes such days says how many.
struct BaselineProposalRow: View {
    let slot: MealSlot
    let text: String
    let isAccepting: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: slot.symbolName)
                    .foregroundStyle(.tint)
                Text("You usually have this for \(slot.displayName.lowercased())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(text)
            Text("Accepting puts these in Health and counts the day as assumed, not complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(action: onAccept) {
                    if isAccepting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isAccepting)
                Button("Not today", action: onDecline)
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            // Not yet logged, said with structure rather than with colour.
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .foregroundStyle(.tertiary)
                .frame(width: 2)
                .offset(x: -10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Proposed \(slot.displayName): \(text). Not logged yet.")
        .accessibilityHint("Accepting puts these in Health and counts the day as assumed.")
    }
}

/// The one line that accounts for a proposal that is no longer on screen.
///
/// Logging into a slot removes that slot's proposal, and the removal is right: a card
/// proposing lunch next to the lunch the user just typed would be offering to log a meal
/// they already logged. But a card someone was looking at a second ago that is silently
/// gone reads as the app losing it rather than as the app agreeing, which is the surprise
/// the copy rule exists to prevent. So the disappearance gets a sentence, in the secondary
/// ink, under the meal that caused it rather than next to the proposals that are left —
/// it is about the meal, and that is where it will be read as an answer.
///
/// What it does not say is the point of it. No comparison with what the usual line would
/// have come to, no remark that the meal was unusual, and no offer to update the baseline.
/// The baseline follows the data; the data is never asked to follow the baseline.
struct DisplacedBaselineNote: View {
    let slot: MealSlot

    var body: some View {
        Text("Replaced your usual \(slot.displayName.lowercased()).")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("A proposed breakfast", traits: .sizeThatFitsLayout) {
    List {
        BaselineProposalRow(
            slot: .breakfast, text: "oats with a banana and coffee",
            isAccepting: false, onAccept: {}, onDecline: {}
        )
    }
}

#Preview("Accepting", traits: .sizeThatFitsLayout) {
    List {
        BaselineProposalRow(
            slot: .lunch, text: "chicken salad", isAccepting: true, onAccept: {}, onDecline: {}
        )
    }
}

#Preview("A displaced proposal", traits: .sizeThatFitsLayout) {
    List {
        DisplacedBaselineNote(slot: .lunch)
            .listRowBackground(Color.clear)
    }
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        BaselineProposalRow(
            slot: .breakfast, text: "oats with a banana and coffee",
            isAccepting: false, onAccept: {}, onDecline: {}
        )
        DisplacedBaselineNote(slot: .lunch)
            .listRowBackground(Color.clear)
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
