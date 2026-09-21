import SwiftUI

/// All eight totals, always visible: four primary large, four secondary small.
/// Falls back to a single column when the type size makes two rows of four too wide.
struct TotalsRow: View {
    let totals: Nutrition

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    ForEach(Nutrient.primary, id: \.self) { nutrient in
                        TotalCell(nutrient: nutrient, value: totals[nutrient], emphasized: true)
                    }
                }
                GridRow {
                    ForEach(Nutrient.secondary, id: \.self) { nutrient in
                        TotalCell(nutrient: nutrient, value: totals[nutrient], emphasized: false)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    TotalCell(nutrient: nutrient, value: totals[nutrient], emphasized: nutrient.isPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct TotalCell: View {
    let nutrient: Nutrient
    let value: Double?
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nutrient.shortName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Formatters.amount(value, unit: nutrient.unit))
                .font(emphasized ? .title3.weight(.semibold) : .subheadline)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nutrient.displayName) \(Formatters.amount(value, unit: nutrient.unit))")
    }
}
