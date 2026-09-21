import Foundation

/// Pure arithmetic behind recipes: raw ingredient weights become a total, a per-serving
/// figure and, at log time, a frozen snapshot. No SwiftData, so it is tested directly.
///
/// Missing nutrients follow `Nutrition.+`: a nutrient stays `nil` only when every
/// ingredient lacks it; otherwise the ingredients that lack it count as 0 in the sum.
/// An ingredient list of zero rows totals `Nutrition.empty` and weighs nothing.
nonisolated enum RecipeMath {
    /// Sum of the raw weights and of each ingredient's per-100 g values scaled to its grams.
    static func total(ingredients: [(grams: Double, per100g: Nutrition)]) -> (weight: Double, nutrition: Nutrition) {
        let weight = ingredients.reduce(0) { $0 + $1.grams }
        let nutrition = ingredients.reduce(Nutrition.empty) { $0 + $1.per100g.scaled(toGrams: $1.grams) }
        return (weight, nutrition)
    }

    /// `total` divided by `servings`. A servings count of 0 or less is treated as 1
    /// rather than producing infinities; callers validate before storing.
    static func perServing(total: Nutrition, servings: Double) -> Nutrition {
        guard servings > 0 else { return total }
        return total.map { $0 / servings }
    }

    /// Raw grams in one serving, with the same guard on `servings` as `perServing`.
    static func gramsPerServing(weight: Double, servings: Double) -> Double {
        guard servings > 0 else { return weight }
        return weight / servings
    }

    /// The nutrition to freeze when logging `servings` portions; fractions are fine.
    static func snapshot(perServing: Nutrition, servings: Double) -> Nutrition {
        perServing.map { $0 * servings }
    }
}
