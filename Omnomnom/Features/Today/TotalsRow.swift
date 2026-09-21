import SwiftUI

/// All eight totals, always visible: four primary large, four secondary small.
/// Falls back to a single column when the type size makes two rows of four too wide.
/// With `foreign` set, the figures include what other sources wrote to Health and a
/// small line says how much of the energy that is; a report, never a verdict.
struct TotalsRow: View {
    let totals: Nutrition
    /// Amounts other sources wrote to Health for the day; `nil` when there are none.
    var foreign: Nutrition? = nil

    private var combined: Nutrition {
        foreign.map { totals + $0 } ?? totals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        ForEach(Nutrient.primary, id: \.self) { nutrient in
                            TotalCell(nutrient: nutrient, value: combined[nutrient], emphasized: true)
                        }
                    }
                    GridRow {
                        ForEach(Nutrient.secondary, id: \.self) { nutrient in
                            TotalCell(nutrient: nutrient, value: combined[nutrient], emphasized: false)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        TotalCell(nutrient: nutrient, value: combined[nutrient], emphasized: nutrient.isPrimary)
                    }
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
    }

    /// "incl. 250 kcal from Health", or a wording without a figure when energy is absent.
    static func foreignNote(_ foreign: Nutrition) -> String {
        if let energy = foreign.energy, energy > 0 {
            return "incl. \(Formatters.amount(energy, unit: .kilocalorie)) from Health"
        }
        return "incl. nutrients from Health"
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
