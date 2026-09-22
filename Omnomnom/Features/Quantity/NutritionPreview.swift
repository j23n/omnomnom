import DeveloperToolsSupport
import SwiftUI

/// Live nutrition for the typed amount, eight cells, no judgment.
struct NutritionPreview: View {
    let nutrition: Nutrition

    private let columns = [GridItem(.adaptive(minimum: 88), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Nutrient.allCases, id: \.self) { nutrient in
                VStack(alignment: .leading, spacing: 2) {
                    Text(nutrient.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Formatters.amount(nutrition[nutrient], unit: nutrient.unit))
                        .font(nutrient.isPrimary ? .body.weight(.semibold) : .body)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Per serving", traits: .sizeThatFitsLayout) {
    NutritionPreview(nutrition: PreviewStore.recipeChoice.perUnit)
        .padding()
}

#Preview("Nothing typed yet", traits: .sizeThatFitsLayout) {
    NutritionPreview(nutrition: .zero)
        .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    NutritionPreview(nutrition: PreviewStore.recipeChoice.perUnit)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
