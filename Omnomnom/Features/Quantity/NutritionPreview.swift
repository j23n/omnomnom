import DeveloperToolsSupport
import SwiftUI

/// Live nutrition for the typed amount, eight cells, no judgment. Energy, protein,
/// carbohydrates and fat lead in one row with the four others under them; when the
/// type size no longer fits four across, the cells go two across, then one under the
/// other, like the totals on Today.
struct NutritionPreview: View {
    let nutrition: Nutrition

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow { cells(Nutrient.primary) }
                GridRow { cells(Nutrient.secondary) }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow { cells(Array(Nutrient.primary.prefix(2))) }
                GridRow { cells(Array(Nutrient.primary.dropFirst(2))) }
                GridRow { cells(Array(Nutrient.secondary.prefix(2))) }
                GridRow { cells(Array(Nutrient.secondary.dropFirst(2))) }
            }
            VStack(alignment: .leading, spacing: 8) {
                cells(Nutrient.allCases)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cells(_ nutrients: [Nutrient]) -> some View {
        ForEach(nutrients, id: \.self) { nutrient in
            PreviewCell(nutrient: nutrient, value: nutrition[nutrient])
        }
    }
}

/// Label over value, sized to its content so the grid measures what it really needs.
private struct PreviewCell: View {
    let nutrient: Nutrient
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nutrient.shortName)
                .font(.caption)
                .foregroundStyle(.secondary)
            ValueText(value, unit: nutrient.unit)
                .font(nutrient.isPrimary ? .body.weight(.semibold) : .body)
        }
        .gridColumnAlignment(.leading)
        .accessibilityElement(children: .combine)
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
