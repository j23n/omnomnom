import SwiftUI

/// Name, the amount field with its range hint, and the shortcut chips.
struct AmountSection: View {
    let choice: FoodChoice
    let chips: [AmountChip]
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    private var unit: AmountUnit { AmountUnit(choice: choice) }

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
            AmountChips(chips: chips) { value in
                text = Formatters.fieldText(value)
            }
        }
    }
}
