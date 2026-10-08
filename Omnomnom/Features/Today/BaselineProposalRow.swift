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

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        BaselineProposalRow(
            slot: .breakfast, text: "oats with a banana and coffee",
            isAccepting: false, onAccept: {}, onDecline: {}
        )
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
