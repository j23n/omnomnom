import Foundation
import SwiftUI

/// Name, grams and energy for one entry, plus a badge when Health does not hold it fully.
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
                    Text(Formatters.grams(entry.grams))
                    Text(entry.timestamp, style: .time)
                    if let badge = entry.healthState.badge {
                        Text(badge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
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
