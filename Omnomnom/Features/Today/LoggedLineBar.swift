import DeveloperToolsSupport
import Foundation
import SwiftUI

/// What was last logged, with the way back from it.
///
/// Not a notice, which is why it is on no timer: two paths write in one tap and nothing
/// else — a widget tap, and accepting a usual meal — and for those this is the only way
/// back. After a line signed off on the sign-off screen it is a courtesy rather than a
/// necessity, and it reads the same either way. It stays until the next send, until the day
/// changes or until it is dismissed, where the transient banner beside it goes after four
/// seconds.
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

#if DEBUG
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

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    LoggedLineBar(
        logged: LoggedLine(
            line: "pancake", entryIDs: [UUID(), UUID()], marked: 1, failed: 1,
            notes: ["Logged here only. Health didn't accept it."]
        ),
        onUndo: {}, onDismiss: {}
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
