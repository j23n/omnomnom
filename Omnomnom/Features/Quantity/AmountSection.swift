import SwiftUI

/// Name, the amount field with its range hint, the shortcut chips and, for a recipe,
/// the one line that says what a serving is a portion of.
struct AmountSection: View {
    let choice: FoodChoice
    let chips: [AmountChip]
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    private var unit: AmountUnit { choice.isRecipe ? .servings : .grams }

    var body: some View {
        Section {
            Text(choice.name)
                .font(.headline)
            if let brand = choice.attribution?.brand {
                Text(brand)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            AmountField(text: $text, unit: unit, isFocused: isFocused)
            if !text.isEmpty, unit.parse(text) == nil {
                Text("Enter between \(unit.rangeText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if choice.isRecipe {
                Text("Servings are portions of the raw total")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            AmountChips(chips: chips) { value in
                text = Formatters.fieldText(value)
            }
        }
    }
}
