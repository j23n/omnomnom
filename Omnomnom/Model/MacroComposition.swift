import Foundation

/// Where a day's energy came from: the shape the composition bar and the day mark both draw.
///
/// Shares of energy rather than grams, because the question the overview answers is what a
/// day was made of and not how much of it there was. The macronutrients are reconstructed
/// from their own energy densities, which never quite agree with the table's own
/// kilocalorie figure, so whatever the three do not account for is carried as
/// `unattributed` and drawn rather than divided away into the ones that are known.
nonisolated struct MacroComposition: Hashable, Sendable {
    /// Kilocalories from protein.
    let protein: Double
    /// Kilocalories from carbohydrate.
    let carbohydrates: Double
    /// Kilocalories from fat.
    let fat: Double
    /// Kilocalories the three above do not account for. Zero when they account for all of it.
    let unattributed: Double
    /// Macronutrients no row had a figure for.
    ///
    /// Their energy is zero here, and that is a gap rather than a measurement: a bar drawn
    /// from this says so with a hatch, and a total built on it is a floor rather than a total.
    let missing: Set<Nutrient>

    /// Kilocalories per gram, in one place.
    ///
    /// A fact rather than a tuning decision, and shared because the square in the day mark
    /// and the bar on Shape must never disagree about it.
    static let kilocaloriesPerGram: [Nutrient: Double] = [
        .protein: 4,
        .carbohydrates: 4,
        .fatTotal: 9,
    ]

    /// The macronutrients, in the order they are always drawn. Never reordered by size.
    static let macronutrients: [Nutrient] = [.protein, .carbohydrates, .fatTotal]

    init(protein: Double, carbohydrates: Double, fat: Double, unattributed: Double, missing: Set<Nutrient> = []) {
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.unattributed = unattributed
        self.missing = missing
    }

    /// Reads a composition out of absolute amounts: an entry, a meal or a whole day.
    ///
    /// Two directions of disagreement, handled differently on purpose. Where the energy
    /// figure is the larger, the difference is a real gap and is kept. Where the
    /// macronutrients claim more energy than the row's own figure — rounding, or a table
    /// using a different convention — the energy figure is the one that gives way, because
    /// shrinking the measured macronutrients to fit it would be inventing a correction.
    /// Either way the shares sum to one and nothing is hidden.
    init(of nutrition: Nutrition) {
        var absent: Set<Nutrient> = []
        func kilocalories(of nutrient: Nutrient) -> Double {
            guard let grams = nutrition[nutrient] else {
                absent.insert(nutrient)
                return 0
            }
            return max(grams, 0) * (Self.kilocaloriesPerGram[nutrient] ?? 0)
        }

        let fromProtein = kilocalories(of: .protein)
        let fromCarbohydrates = kilocalories(of: .carbohydrates)
        let fromFat = kilocalories(of: .fatTotal)
        let accounted = fromProtein + fromCarbohydrates + fromFat
        let energy = max(nutrition.energy ?? 0, 0)

        self.init(
            protein: fromProtein,
            carbohydrates: fromCarbohydrates,
            fat: fromFat,
            unattributed: max(energy - accounted, 0),
            missing: absent
        )
    }

    /// Nothing at all: an empty day.
    static let empty = MacroComposition(protein: 0, carbohydrates: 0, fat: 0, unattributed: 0)

    /// The denominator every share is taken against.
    var total: Double { protein + carbohydrates + fat + unattributed }

    /// Whether there is anything to draw.
    var isEmpty: Bool { total <= 0 }

    /// Kilocalories from one macronutrient, or 0 for anything that is not one.
    func kilocalories(of nutrient: Nutrient) -> Double {
        switch nutrient {
        case .protein: protein
        case .carbohydrates: carbohydrates
        case .fatTotal: fat
        default: 0
        }
    }

    /// One macronutrient's share of the energy, 0 to 1. Zero for an empty composition.
    func share(of nutrient: Nutrient) -> Double {
        guard total > 0 else { return 0 }
        return kilocalories(of: nutrient) / total
    }

    /// The share no macronutrient accounts for, 0 to 1.
    var unattributedShare: Double {
        guard total > 0 else { return 0 }
        return unattributed / total
    }

    /// One band of the bar, or one band of the square in the day mark.
    nonisolated struct Band: Hashable, Sendable, Identifiable {
        /// The macronutrient this band is, or `nil` for the part none of them accounts for.
        let nutrient: Nutrient?
        let kilocalories: Double
        /// 0 to 1, against the whole composition.
        let share: Double

        var id: String { nutrient?.rawValue ?? "unattributed" }
    }

    /// The bands to draw, in fixed order, leaving out the ones that would be a sliver.
    ///
    /// Protein, carbohydrate, fat, then whatever is unaccounted for — the same order
    /// every time, because a band that moves between days cannot be read across them. A
    /// macronutrient contributing no energy is left out rather than drawn as a hairline;
    /// that it was missing rather than zero is in `missing`, which is what carries the
    /// hatch.
    var bands: [Band] {
        var bands: [Band] = Self.macronutrients.compactMap { nutrient in
            let kilocalories = kilocalories(of: nutrient)
            guard kilocalories > 0 else { return nil }
            return Band(nutrient: nutrient, kilocalories: kilocalories, share: share(of: nutrient))
        }
        if unattributed > 0 {
            bands.append(Band(nutrient: nil, kilocalories: unattributed, share: unattributedShare))
        }
        return bands
    }
}
