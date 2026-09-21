import SwiftUI

/// One ingredient in the builder: name and its energy, with the gram field inline.
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
            TextField("0", text: $ingredient.gramsText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .foregroundStyle(ingredient.grams == nil ? Color.red : Color.primary)
                .accessibilityLabel("Grams of \(ingredient.name)")
                .accessibilityValue(ingredient.gramsText.isEmpty ? "no amount" : "\(ingredient.gramsText) grams")
            Text("g")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
