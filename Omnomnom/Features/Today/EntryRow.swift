import Foundation
import SwiftUI

/// Name, grams and energy for one entry, plus a badge when Health does not hold it fully.
struct EntryRow: View {
    let entry: LogEntry

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
    }
}
