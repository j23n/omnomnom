import SwiftUI

/// One row of the resolution sheet.
///
/// Three tiers, encoded by structure rather than by colour, because no colour in this
/// app may carry a verdict and a chart or a row that grades what someone ate is the one
/// thing the design will not do.
///
/// - A **settled** row is quiet: name, amount, and one line saying where it came from.
///   No chevron, nothing to do.
/// - A row **worth a glance** keeps the same shape and gains a chevron, so it is tappable
///   and reads as having an alternative. It is found reliably by the count above the Log
///   button rather than by its own appearance, which is a deliberate trade and the thing
///   most worth testing on a real person.
/// - A row that **blocks** has no food at all, so it shows no figures — there are none to
///   show — and offers the one control that gets past it.
struct ResolutionRowView: View {
    let row: ResolvedRow
    /// Whether the model checked this line's matches. A property of the screen, passed
    /// down, because it can never be true of one row and false of another.
    let checked: Bool
    let onPick: () -> Void

    var body: some View {
        if row.choice == nil {
            blocked
        } else {
            matched
        }
    }

    private var matched: some View {
        Button(action: onPick) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(amountText)
                        .monospacedDigit()
                    if let energy = row.nutrition?.energy {
                        Text(Formatters.amount(energy, unit: .kilocalorie))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if !row.isSettled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityHint(row.isSettled ? "" : "Opens a list of other foods")
    }

    private var blocked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.name)
            Text("No food found for this.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Pick a food", systemImage: "magnifyingglass", action: onPick)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name). No food found. Pick a food, or swipe to remove.")
    }

    /// The line under the name. Says what happened, never how much to trust it.
    private var detail: String {
        var text = row.origin.detail(checked: checked)
        if row.implausible {
            text += " · that is a lot for one item"
        }
        return text
    }

    /// The amount, with the step it came from when there was one to come from.
    private var amountText: String {
        guard let choice = row.choice else { return "" }
        let figure: String = if case .recipe = choice.source {
            Formatters.servings(row.amount)
        } else {
            Formatters.amount(row.amount, measure: choice.measure)
        }
        guard let bucket = row.bucket, bucket != .usual else { return figure }
        return "\(bucket.label) · \(figure)"
    }

    private var accessibility: String {
        var parts = [row.displayName, amountText, detail]
        if let energy = row.nutrition?.energy {
            parts.insert(Formatters.amount(energy, unit: .kilocalorie), at: 2)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

#if DEBUG
private func row(
    _ name: String, amount: Double, origin: RowOrigin, confidence: MatchConfidence,
    matched: Bool = true, implausible: Bool = false, bucket: AmountBucket? = nil
) -> ResolvedRow {
    ResolvedRow(
        name: name,
        choice: matched
            ? FoodChoice(
                source: .bundled(id: 1), name: name,
                perUnit: Nutrition(energy: 370, protein: 13, carbohydrates: 60, fatTotal: 7)
            )
            : nil,
        amount: amount,
        bucket: bucket,
        origin: origin,
        confidence: confidence,
        implausible: implausible
    )
}

#Preview("The three tiers", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .phrase, confidence: .settled, bucket: .usual), checked: false) {}
        ResolutionRowView(row: row("Coffee with milk", amount: 200, origin: .database, confidence: .probable), checked: true) {}
        ResolutionRowView(row: row("something unusual", amount: 0, origin: .database, confidence: .unsure, matched: false), checked: true) {}
    }
}

#Preview("Unchecked and implausible", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .database, confidence: .settled), checked: false) {}
        ResolutionRowView(row: row("Coffee, instant, powder", amount: 200, origin: .database, confidence: .probable, implausible: true), checked: false) {}
    }
}

#Preview("A bigger step", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Lentil soup", amount: 420, origin: .item, confidence: .settled, bucket: .more), checked: true) {}
    }
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .phrase, confidence: .settled, bucket: .usual), checked: false) {}
        ResolutionRowView(row: row("something unusual", amount: 0, origin: .database, confidence: .unsure, matched: false), checked: true) {}
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
