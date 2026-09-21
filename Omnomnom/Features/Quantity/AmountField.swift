import SwiftUI

/// The unit an `AmountField` collects: grams for a food, servings for a recipe.
nonisolated enum AmountUnit: Sendable {
    case grams
    case servings

    /// Shown after the field.
    var symbol: String {
        switch self {
        case .grams: "g"
        case .servings: "servings"
        }
    }

    /// VoiceOver label for the field.
    var accessibilityLabel: String {
        switch self {
        case .grams: "Grams"
        case .servings: "Servings"
        }
    }

    /// The typed amount, or `nil` when it is empty, not a number or out of range.
    func parse(_ text: String) -> Double? {
        switch self {
        case .grams: Formatters.parseGrams(text)
        case .servings: Formatters.parseServings(text)
        }
    }

    /// "0.1 and 5000 g", for the inline hint when the text is out of range.
    var rangeText: String {
        switch self {
        case .grams: Formatters.gramsRangeText
        case .servings: Formatters.servingsRangeText
        }
    }
}

/// The canonical amount field: decimal pad, one unit, VoiceOver reads the unit.
struct AmountField: View {
    @Binding var text: String
    let unit: AmountUnit
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .focused(isFocused)
                .accessibilityLabel(unit.accessibilityLabel)
                .accessibilityValue(text.isEmpty ? "no amount" : "\(text) \(unit.symbol)")
            Text(unit.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
