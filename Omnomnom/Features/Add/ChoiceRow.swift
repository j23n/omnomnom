import DeveloperToolsSupport
import SwiftUI

/// One recipe or stored food in the Add sheet: name, the amount used last time and
/// energy per unit ("per 100 g" for a food, "per serving" for a recipe). A product
/// adds its brand and, when fetched from there, names Open Food Facts.
struct ChoiceRow: View {
    let choice: FoodChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(choice.name)
            HStack(spacing: 6) {
                if let brand = choice.attribution?.brand {
                    Text(brand)
                }
                if let last = choice.lastAmount {
                    Text("Last \(choice.amountText(last))")
                }
                Text("\(Formatters.amount(choice.perUnit.energy, unit: .kilocalorie)) per \(choice.unitText)")
                if choice.attribution?.isFromOpenFoodFacts == true {
                    Text("Open Food Facts")
                }
            }
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
