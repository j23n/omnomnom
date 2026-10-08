import DeveloperToolsSupport
import SwiftUI

/// All eight totals, always visible. Energy leads on its own line in the rounded face at
/// bold weight, the one figure in the app set that way; protein, carbohydrates
/// and fat follow larger than saturated fat, fiber, sugar and sodium. The grid gives way
/// to one column when the type size no longer fits it across. With `foreign` set, a small
/// line says how much of the energy other sources wrote to Health; a report, never a
/// verdict.
struct TotalsRow: View {
    /// What the day comes to, local entries and foreign Health samples together: the same
    /// figure the mark and the bar above are drawn from, summed once by the day rather than
    /// again here, so the two cannot drift apart.
    let totals: Nutrition
    /// Which part of those totals other sources wrote to Health; `nil` when there are none.
    /// Read only for the line underneath, since `totals` already holds it.
    var foreign: Nutrition? = nil

    /// Which three sit beside energy. A width constraint, chosen by the user, never a
    /// statement about which nutrients matter; see `HeadlineNutrients`.
    @AppStorage(HeadlineNutrients.key) private var rawHeadline = HeadlineNutrients.encode(HeadlineNutrients.standard)

    private var large: [Nutrient] { HeadlineNutrients.decode(rawHeadline) }
    private var small: [Nutrient] { HeadlineNutrients.secondary(to: large) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NutrientCell(nutrient: .energy, value: totals.energy, font: .system(.largeTitle, design: .rounded, weight: .bold))
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        cells(large, font: .title3.weight(.semibold))
                    }
                    GridRow {
                        cells(small, font: .body)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    cells(large, font: .title3.weight(.semibold))
                    cells(small, font: .body)
                }
            }
            if let foreign {
                Text(Self.foreignNote(foreign))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily totals")
    }

    private func cells(_ nutrients: [Nutrient], font: Font) -> some View {
        ForEach(nutrients, id: \.self) { nutrient in
            NutrientCell(nutrient: nutrient, value: totals[nutrient], font: font)
        }
    }

    /// "incl. 250 kcal from Health", or a wording without a figure when energy is absent.
    static func foreignNote(_ foreign: Nutrition) -> String {
        if let energy = foreign.energy, energy > 0 {
            return "incl. \(Formatters.amount(energy, unit: .kilocalorie)) from Health"
        }
        return "incl. nutrients from Health"
    }
}

#if DEBUG
#Preview("Typical", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: PreviewFoods.dayTotals)
        .padding()
}

#Preview("With foreign", traits: .sizeThatFitsLayout) {
    TotalsRow(
        totals: PreviewFoods.dayTotals + PreviewFoods.foreignTotals,
        foreign: PreviewFoods.foreignTotals
    )
    .padding()
}

#Preview("Empty day", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: .zero)
        .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    TotalsRow(
        totals: PreviewFoods.dayTotals + PreviewFoods.foreignTotals,
        foreign: PreviewFoods.foreignTotals
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
