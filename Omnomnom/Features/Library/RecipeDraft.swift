import Foundation

/// One ingredient row while editing: the frozen copy of the food plus the typed grams.
nonisolated struct IngredientDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Where the food came from, to link the row for display; `nil` when that row is gone.
    let source: FoodChoice.Source?
    let name: String
    let per100g: Nutrition
    var gramsText: String

    /// The typed grams, or `nil` while the text is empty, not a number or out of range.
    var grams: Double? {
        Formatters.parseGrams(gramsText)
    }

    /// Energy for the typed grams; `nil` while the grams are not valid.
    var energy: Double? {
        grams.flatMap { per100g.scaled(toGrams: $0).energy }
    }
}

/// Value-type state of the recipe builder. Cancel drops it; Done applies it to the
/// model through `RecipeWriter`, so nothing is stored while editing.
nonisolated struct RecipeDraft: Hashable, Sendable {
    var name = ""
    var servings = 1.0
    var ingredients: [IngredientDraft] = []

    /// Grams a freshly added ingredient starts with; edited inline.
    static let defaultGrams = 100.0
    static let minimumServings = 0.5
    static let maximumServings = 100.0

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rows with a valid gram amount; a row being typed counts as nothing until it parses.
    var rows: [(grams: Double, per100g: Nutrition)] {
        ingredients.compactMap { row in
            row.grams.map { (grams: $0, per100g: row.per100g) }
        }
    }

    var totalWeight: Double {
        RecipeMath.total(ingredients: rows).weight
    }

    var perServing: Nutrition {
        RecipeMath.perServing(total: RecipeMath.total(ingredients: rows).nutrition, servings: servings)
    }

    var gramsPerServing: Double {
        RecipeMath.gramsPerServing(weight: totalWeight, servings: servings)
    }

    /// A name, a sensible servings count, and at least one row, every row with valid grams.
    var isValid: Bool {
        !trimmedName.isEmpty
            && (Self.minimumServings...Self.maximumServings).contains(servings)
            && !ingredients.isEmpty
            && ingredients.allSatisfy { $0.grams != nil }
    }

    /// Appends a food at `defaultGrams`. A recipe is ignored: recipes do not nest.
    mutating func add(_ choice: FoodChoice) {
        guard !choice.isRecipe else { return }
        ingredients.append(IngredientDraft(
            id: UUID(),
            source: choice.source,
            name: choice.name,
            per100g: choice.perUnit,
            gramsText: Formatters.fieldText(Self.defaultGrams)
        ))
    }
}
