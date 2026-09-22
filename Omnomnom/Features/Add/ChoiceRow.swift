import DeveloperToolsSupport
import SwiftUI

/// One recipe or stored food in the Add sheet: name, the amount used last time and
/// energy per unit ("per 100 g" for a food, "per serving" for a recipe). A product
/// adds its brand and, when fetched from there, names Open Food Facts.
struct ChoiceRow: View {
    let choice: FoodChoice

    /// "Whole Earth · Last 30 g · 588 kcal per 100 g · Open Food Facts", wrapping as one line of text.
    private var caption: String {
        var parts: [String] = []
        if let brand = choice.attribution?.brand {
            parts.append(brand)
        }
        if let last = choice.lastAmount {
            parts.append("Last \(choice.amountText(last))")
        }
        parts.append("\(Formatters.amount(choice.perUnit.energy, unit: .kilocalorie)) per \(choice.unitText)")
        if choice.attribution?.isFromOpenFoodFacts == true {
            parts.append("Open Food Facts")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(choice.name)
            ValueText(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Recipe, custom, products", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ChoiceRow(choice: PreviewStore.recipeChoice)
        ChoiceRow(choice: PreviewStore.customChoice)
        ChoiceRow(choice: PreviewStore.productChoice)
        ChoiceRow(choice: PreviewStore.manualProductChoice)
        ChoiceRow(choice: PreviewStore.bundledChoice)
    }
    .padding()
}
#endif
