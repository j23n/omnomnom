import DeveloperToolsSupport
import Foundation
import SwiftUI

/// What the last send wrote, with the way back from it.
///
/// A line is logged without being signed off, so this is not a notice: it is the other
/// half of that decision. It stays until the next send, until the day changes or until it
/// is dismissed, where the transient banner beside it goes after four seconds. A window on
/// a clock is the wrong shape for the only way back from a write nobody confirmed.
///
/// Dismissing it is not another way of keeping the entries — they are kept either way, and
/// the day's own rows are where one of them gets removed on its own.
struct LoggedLineBar: View {
    let logged: LoggedLine
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(logged.message)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if logged.canUndo {
                Button("Undo", action: onUndo)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHint("Removes what this line just logged")
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The part of a line nothing could be placed, which is the one question a send ever asks.
///
/// It asks after the fact and beside the field rather than in the way of it: what the line
/// got right is already in the day, and this is about the one food that is not. Leaving it
/// drops the words, which is honest — nothing was logged for them, so there is nothing to
/// correct later.
struct UnplacedRowsBar: View {
    let note: String
    let onPick: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note)
                .font(.footnote)
                .multilineTextAlignment(.leading)
            HStack(spacing: 16) {
                Button("Choose a food", action: onPick)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHint("Opens what the line said so you can name the food")
                Button("Leave it", action: onLeave)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Drops the question. Nothing was logged for it")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
private let oneItem = LoggedLine(
    line: "oats, banana, coffee", entryIDs: [UUID()], marked: 0, failed: 0
)

#Preview("A clean send", traits: .sizeThatFitsLayout) {
    LoggedLineBar(
        logged: LoggedLine(
            line: "oats, banana, coffee", entryIDs: [UUID(), UUID(), UUID()], marked: 0, failed: 0
        ),
        onUndo: {}, onDismiss: {}
    )
    .padding()
}

#Preview("Something wants a look", traits: .sizeThatFitsLayout) {
    LoggedLineBar(
        logged: LoggedLine(
            line: "pancake with peanut butter", entryIDs: [UUID(), UUID()], marked: 1, failed: 0
        ),
        onUndo: {}, onDismiss: {}
    )
    .padding()
}

#Preview("Health refused it", traits: .sizeThatFitsLayout) {
    LoggedLineBar(
        logged: LoggedLine(
            line: "chicken salad", entryIDs: [UUID()], marked: 0, failed: 0,
            notes: ["Logged here only. Health didn't accept it."]
        ),
        onUndo: {}, onDismiss: {}
    )
    .padding()
}

#Preview("Nothing was logged", traits: .sizeThatFitsLayout) {
    LoggedLineBar(
        logged: LoggedLine(line: "something", entryIDs: [], marked: 0, failed: 2),
        onUndo: {}, onDismiss: {}
    )
    .padding()
}

#Preview("A question outstanding", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        LoggedLineBar(logged: oneItem, onUndo: {}, onDismiss: {})
        UnplacedRowsBar(note: "1 food needs a word from you.", onPick: {}, onLeave: {})
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        LoggedLineBar(
            logged: LoggedLine(
                line: "pancake", entryIDs: [UUID(), UUID()], marked: 1, failed: 1,
                notes: ["Logged here only. Health didn't accept it."]
            ),
            onUndo: {}, onDismiss: {}
        )
        UnplacedRowsBar(note: "2 foods need a word from you.", onPick: {}, onLeave: {})
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
