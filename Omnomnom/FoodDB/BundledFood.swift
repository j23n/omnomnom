import Foundation

/// One row of the bundled `foods` table.
nonisolated struct BundledFood: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let category: String?
    let per100g: Nutrition
    let popularity: Int
    /// The same food in the source's other languages. Never displayed, but scored
    /// against: the FTS index finds a Ciqual row by its French name while the row
    /// reads in English, and a matcher that only saw `name` would score that hit at
    /// nothing and refuse to match in any language but the one on screen.
    let altNames: [String]
    /// An ingredient or a dry, raw or concentrated form rather than a portion anyone
    /// eats: coffee powder, dried milk, raw chicken, oil. Set by the build from named
    /// rules. The matcher demotes these heavily and never settles on one, because they
    /// answer the same words as the food that was meant and hold figures for something
    /// else. See `reasons` in `Tools/fooddb/fooddb/ingredient.py`.
    let isIngredient: Bool

    init(
        id: Int,
        name: String,
        category: String?,
        per100g: Nutrition,
        popularity: Int,
        altNames: [String] = [],
        isIngredient: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.per100g = per100g
        self.popularity = popularity
        self.altNames = altNames
        self.isIngredient = isIngredient
    }

    /// Every text this row can be found and scored by, display name first.
    var searchableNames: [String] { [name] + altNames }
}

/// A household measure for a bundled food, such as "1 medium" at 182 g.
nonisolated struct Portion: Hashable, Sendable {
    let label: String
    let grams: Double
}
