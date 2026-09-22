import SwiftUI

/// One ingredient in the builder: name and its energy, with the amount field inline in
/// the food's own unit, grams or millilitres.
struct IngredientRow: View {
    @Binding var ingredient: IngredientDraft

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                Text(Formatters.amount(ingredient.energy, unit: .kilocalorie))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", text: $ingredient.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .foregroundStyle(ingredient.amount == nil ? Color.red : Color.primary)
                .accessibilityLabel("\(ingredient.measure.displayName) of \(ingredient.name)")
                .accessibilityValue(
                    ingredient.amountText.isEmpty
                        ? "no amount"
                        : "\(ingredient.amountText) \(ingredient.measure.spokenName)"
                )
            Text(ingredient.measure.unitSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
