import Foundation

/// Pure arithmetic behind recipes: raw ingredient amounts become a total, a per-serving
/// figure and, at log time, a frozen snapshot. No SwiftData, so it is tested directly.
///
/// Ingredients need not share a unit, so the raw total is a `RawAmount` that carries
/// mass and volume apart. The nutrition is unaffected: each row is scaled by its own
/// amount against its own per-100 values, and a serving is the same fraction of the
/// whole dish whichever units went into it.
///
/// Missing nutrients follow `Nutrition.+`: a nutrient stays `nil` only when every
/// ingredient lacks it; otherwise the ingredients that lack it count as 0 in the sum.
/// An ingredient list of zero rows totals `Nutrition.empty` and amounts to nothing.
nonisolated enum RecipeMath {
    /// Sum of the raw amounts, mass and volume apart, and of each ingredient's per-100
    /// values scaled to its own amount.
    static func total(
        ingredients: [(amount: Double, measure: FoodMeasure, per100: Nutrition)]
    ) -> (amount: RawAmount, nutrition: Nutrition) {
        let amount = ingredients.reduce(RawAmount.zero) { $0 + RawAmount($1.amount, measure: $1.measure) }
        let nutrition = ingredients.reduce(Nutrition.empty) { $0 + $1.per100.scaled(toGrams: $1.amount) }
        return (amount, nutrition)
    }

    /// `total` divided by `servings`. A servings count of 0 or less is treated as 1
    /// rather than producing infinities; callers validate before storing.
    static func perServing(total: Nutrition, servings: Double) -> Nutrition {
        guard servings > 0 else { return total }
        return total.map { $0 / servings }
    }

    /// The raw amount of one serving, each part divided, with the same guard on
    /// `servings` as `perServing`.
    static func amountPerServing(total: RawAmount, servings: Double) -> RawAmount {
        guard servings > 0 else { return total }
        return RawAmount(grams: total.grams / servings, millilitres: total.millilitres / servings)
    }

    /// The nutrition to freeze when logging `servings` portions; fractions are fine.
    static func snapshot(perServing: Nutrition, servings: Double) -> Nutrition {
        perServing.map { $0 * servings }
    }
}
