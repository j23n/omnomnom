import DeveloperToolsSupport
import Foundation
import SwiftUI

/// One shortcut above the amount field: a label and the amount it fills in.
nonisolated struct AmountChip: Hashable, Sendable {
    let label: String
    let value: Double

    /// Household measures of a bundled food, such as "1 medium, 182 g". The bundled
    /// database is per 100 g throughout, so a portion is always a mass.
    static func portions(_ portions: [Portion]) -> [AmountChip] {
        portions.map {
            AmountChip(label: "\($0.label), \(Formatters.amount($0.grams, measure: .mass))", value: $0.grams)
        }
    }

    /// Half, one and two servings of a recipe.
    static let servings: [AmountChip] = [
        AmountChip(label: "½ serving", value: 0.5),
        AmountChip(label: "1 serving", value: 1),
        AmountChip(label: "2 servings", value: 2),
    ]

    /// Steps against what this person last had of this food.
    ///
    /// Offered only where there is a remembered amount to multiply. On a food eaten for
    /// the first time the same control would make "Usual" mean a population average, or
    /// a bare 100 g, so that food gets its portions by name instead and these are simply
    /// absent. A greyed-out row would be worse than an absent one: a disabled control
    /// still teaches that buckets are the real answer and that this food is deficient.
    ///
    /// The resolved amount is in the label beside the step, so the person always sees
    /// both what they chose and what it came to.
    static func buckets(reference: Double, measure: FoodMeasure) -> [AmountChip] {
        AmountBucket.allCases.map { bucket in
            let amount = bucket.amount(of: reference)
            return AmountChip(
                label: "\(bucket.label), \(Formatters.amount(amount, measure: measure))",
                value: amount
            )
        }
    }
}

/// Shortcuts as chips, wrapping onto further rows when they do not fit across. Tapping
/// one fills the amount field; the unit never changes.
struct AmountChips: View {
    let chips: [AmountChip]
    let onSelect: (Double) -> Void

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        onSelect(chip.value)
                    } label: {
                        Text(chip.label)
                            .privacySensitive()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(chip.label)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Portions", traits: .sizeThatFitsLayout) {
    AmountChips(chips: AmountChip.portions([
        Portion(label: "1 medium (3\" dia)", grams: 182),
        Portion(label: "1 cup, chopped", grams: 125),
        Portion(label: "0.5 cup", grams: 62.5),
    ])) { _ in }
    .padding()
}

#Preview("Servings", traits: .sizeThatFitsLayout) {
    AmountChips(chips: AmountChip.servings) { _ in }
        .padding()
}

#Preview("Servings, accessibility 5", traits: .sizeThatFitsLayout) {
    AmountChips(chips: AmountChip.servings) { _ in }
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
