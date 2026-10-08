import SwiftUI

/// A nutrient's short name over its figure, sized to its content so a grid measures what
/// it really needs.
///
/// One cell for the day's totals and for the live preview under a typed amount. They were
/// written separately and had already drifted: only one of them spelled the figure out for
/// VoiceOver, so the same number was read as "Prot 12 g" on one screen and "Protein, 12
/// grams" on the other. The caller chooses the figure's font, because what counts as the
/// large one differs between a screen of totals and a row of eight.
struct NutrientCell: View {
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
