import DeveloperToolsSupport
import SwiftUI

/// All eight totals, always visible. Energy leads on its own line; protein, carbohydrates
/// and fat follow larger than saturated fat, fiber, sugar and sodium. The grid gives way
/// to one column when the type size no longer fits it across. With `foreign` set, the
/// figures include what other sources wrote to Health and a small line says how much of
/// the energy that is; a report, never a verdict.
struct TotalsRow: View {
    let totals: Nutrition
    /// Amounts other sources wrote to Health for the day; `nil` when there are none.
    var foreign: Nutrition? = nil

    private static let large: [Nutrient] = [.protein, .carbohydrates, .fatTotal]
    private static let small: [Nutrient] = [.fatSaturated, .fiber, .sugar, .sodium]

    private var combined: Nutrition {
        foreign.map { totals + $0 } ?? totals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TotalCell(nutrient: .energy, value: combined.energy, font: .title.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        cells(Self.large, font: .title3.weight(.semibold))
                    }
                    GridRow {
                        cells(Self.small, font: .body)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    cells(Self.large, font: .title3.weight(.semibold))
                    cells(Self.small, font: .body)
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
            TotalCell(nutrient: nutrient, value: combined[nutrient], font: font)
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

/// Label over value, sized to its content so the grid measures what it really needs.
private struct TotalCell: View {
    let nutrient: Nutrient
    let value: Double?
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nutrient.shortName)
                .font(.caption)
                .foregroundStyle(.secondary)
            ValueText(value, unit: nutrient.unit)
                .font(font)
        }
        .gridColumnAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nutrient.displayName), \(Formatters.spokenAmount(value, unit: nutrient.unit))")
    }
}

#if DEBUG
#Preview("Typical", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: PreviewFoods.dayTotals)
        .padding()
}

#Preview("With foreign", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: PreviewFoods.dayTotals, foreign: PreviewFoods.foreignTotals)
        .padding()
}

#Preview("Empty day", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: .zero)
        .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    TotalsRow(totals: PreviewFoods.dayTotals, foreign: PreviewFoods.foreignTotals)
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
