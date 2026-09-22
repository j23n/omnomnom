import SwiftUI

/// One item of the estimate: what the model called it, the food its values come from,
/// the portion, and what that portion holds. Only the portion and the food can be
/// changed; no nutrient is typed here, because every number is the database's.
struct EstimateDraftRowView: View {
    @Binding var row: EstimateDraftRow
    /// Opens the food search; the parent owns the sheet, so only one is ever open.
    let onChooseFood: () -> Void
    let onRemove: () -> Void

    /// The matched food, or the one thing left to do on this row.
    private var foodText: String {
        row.choice?.name ?? "Choose a food"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(row.trimmedName.isEmpty ? "item" : row.trimmedName)")
            }
            Button(action: onChooseFood) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(foodText)
                        .font(.callout)
                        .foregroundStyle(row.choice == nil ? Color.accentColor : Color.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.choice == nil ? "Choose a food" : "Values from \(foodText)")
            .accessibilityHint("Opens the food search")
            HStack(spacing: 4) {
                Text("Portion")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $row.gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(row.isGramsInvalid ? Color.red : Color.primary)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Portion in grams")
                Text("g")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let nutrition = row.nutrition {
                HStack(spacing: 4) {
                    ValueText(nutrition.energy, unit: .kilocalorie)
                    Text("for this portion")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
}
