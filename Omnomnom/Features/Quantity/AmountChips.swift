import Foundation
import SwiftUI

/// One shortcut above the amount field: a label and the amount it fills in.
nonisolated struct AmountChip: Hashable, Sendable {
    let label: String
    let value: Double

    /// Household measures of a bundled food, such as "1 medium, 182 g".
    static func portions(_ portions: [Portion]) -> [AmountChip] {
        portions.map { AmountChip(label: "\($0.label), \(Formatters.grams($0.grams))", value: $0.grams) }
    }

    /// Half, one and two servings of a recipe.
    static let servings: [AmountChip] = [
        AmountChip(label: "½ serving", value: 0.5),
        AmountChip(label: "1 serving", value: 1),
        AmountChip(label: "2 servings", value: 2),
    ]
}

/// Shortcuts as chips. Tapping one fills the amount field; the unit never changes.
struct AmountChips: View {
    let chips: [AmountChip]
    let onSelect: (Double) -> Void

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button {
                            onSelect(chip.value)
                        } label: {
                            Text(chip.label)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(chip.label)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
