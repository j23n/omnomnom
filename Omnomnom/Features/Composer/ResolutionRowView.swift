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
    /// The row with its amount changed. Until this existed the sheet showed an amount and
    /// offered no way to change it, which made every first-time food 100 g of itself.
    let onChange: (ResolvedRow) -> Void

    /// Up while an exact figure is being typed.
    @State private var isEditingAmount = false
    /// What is in that field. A string, because a half-typed number is not a number.
    @State private var typedAmount = ""

    var body: some View {
        if row.choice == nil {
            blocked
        } else {
            matched
        }
    }

    /// Two controls, not one.
    ///
    /// The row used to be a single button that opened the food picker, with the amount
    /// drawn inside it as text. The amount is the thing people most want to change, so it
    /// is its own control now and the name keeps the tap that changes the food. They are
    /// separated rather than stacked because one row answering two questions with one tap
    /// can only answer the wrong one.
    private var matched: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(action: onPick) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)
            .accessibilityHint("Opens a list of other foods")

            Spacer(minLength: 12)
            amountControl

            if !row.isSettled {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .alert("Amount", isPresented: $isEditingAmount) {
            TextField("Amount", text: $typedAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") { commitTypedAmount() }
        } message: {
            Text(amountPrompt)
        }
    }

    /// The amount, and the ways to change it.
    ///
    /// A menu rather than four buttons on the row: at accessibility sizes a segmented
    /// control of four words is taller than the row it belongs to, and the steps are not
    /// worth that much of the screen. The amount already reads as a figure, so making it
    /// the control keeps the row the same height it was.
    private var amountControl: some View {
        Menu {
            if row.canStep {
                // The step, and what it comes to, on one line each: the word is what was
                // chosen and the figure is what it means, and neither is much use alone.
                ForEach(AmountBucket.allCases, id: \.self) { bucket in
                    Button {
                        onChange(row.stepped(to: bucket))
                    } label: {
                        Text("\(bucket.label) · \(steppedText(bucket))")
                    }
                }
                Divider()
            }
            Button("Exact amount…") {
                typedAmount = Formatters.prefillText(row.amount)
                isEditingAmount = true
            }
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Amount, \(amountText)")
        .accessibilityHint(row.canStep ? "Choose a step or type an amount" : "Type an amount")
    }

    /// What a step would come to, so the menu names the figure as well as the word.
    private func steppedText(_ bucket: AmountBucket) -> String {
        guard let choice = row.choice else { return "" }
        return Formatters.amount(bucket.amount(of: row.baseAmount), measure: choice.measure)
    }

    /// Reads the field, or leaves the row alone when it does not hold a number.
    ///
    /// Clamped to the bounds the Quantity sheet uses, so one typed figure cannot mean
    /// something the rest of the app would refuse.
    private func commitTypedAmount() {
        let cleaned = typedAmount.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return }
        let clamped = min(max(value, Formatters.minimumAmount), Formatters.maximumAmount)
        onChange(row.set(amount: clamped))
    }

    /// What the alert says above the field: the unit, because the field cannot show one.
    private var amountPrompt: String {
        guard let choice = row.choice else { return row.displayName }
        if case .recipe = choice.source {
            return "\(row.displayName), in servings"
        }
        return "\(row.displayName), in \(choice.measure.spokenName)"
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
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .phrase, confidence: .settled, bucket: .usual), checked: false, onPick: {}, onChange: { _ in })
        ResolutionRowView(row: row("Coffee with milk", amount: 200, origin: .database, confidence: .probable), checked: true, onPick: {}, onChange: { _ in })
        ResolutionRowView(row: row("something unusual", amount: 0, origin: .database, confidence: .unsure, matched: false), checked: true, onPick: {}, onChange: { _ in })
    }
}

#Preview("Unchecked and implausible", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .database, confidence: .settled), checked: false, onPick: {}, onChange: { _ in })
        ResolutionRowView(row: row("Coffee, instant, powder", amount: 200, origin: .database, confidence: .probable, implausible: true), checked: false, onPick: {}, onChange: { _ in })
    }
}

#Preview("A bigger step", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Lentil soup", amount: 420, origin: .item, confidence: .settled, bucket: .more), checked: true, onPick: {}, onChange: { _ in })
    }
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        ResolutionRowView(row: row("Oats, rolled", amount: 40, origin: .phrase, confidence: .settled, bucket: .usual), checked: false, onPick: {}, onChange: { _ in })
        ResolutionRowView(row: row("something unusual", amount: 0, origin: .database, confidence: .unsure, matched: false), checked: true, onPick: {}, onChange: { _ in })
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
