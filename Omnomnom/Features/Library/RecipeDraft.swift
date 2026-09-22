import Foundation

/// One ingredient row while editing: the frozen copy of the food, the unit it is
/// measured in, and the typed amount.
nonisolated struct IngredientDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Where the food came from, to link the row for display; `nil` when that row is gone.
    let source: FoodChoice.Source?
    let name: String
    let per100g: Nutrition
    /// Grams or millilitres, copied from the food; the typed amount is in this unit.
    let measure: FoodMeasure
    var gramsText: String

    /// The typed amount, or `nil` while the text is empty, not a number or out of range.
    var grams: Double? {
        Formatters.parseAmount(gramsText)
    }

    /// Energy for the typed amount; `nil` while the amount is not valid.
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
    /// The stored-size photo of the dish; `nil` for none.
    var photo: Data?

    /// The amount a freshly added ingredient starts with, in its own unit; edited inline.
    static let defaultGrams = 100.0
    static let minimumServings = 0.5
    static let maximumServings = 100.0

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rows with a valid amount; a row being typed counts as nothing until it parses.
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

    /// A name, a sensible servings count, and at least one row, every row with a valid amount.
    var isValid: Bool {
        !trimmedName.isEmpty
            && (Self.minimumServings...Self.maximumServings).contains(servings)
            && !ingredients.isEmpty
            && ingredients.allSatisfy { $0.grams != nil }
    }

    /// Appends a food at `defaultGrams`, in the food's own unit. A recipe is ignored:
    /// recipes do not nest.
    mutating func add(_ choice: FoodChoice) {
        guard !choice.isRecipe else { return }
        ingredients.append(IngredientDraft(
            id: UUID(),
            source: choice.source,
            name: choice.name,
            per100g: choice.perUnit,
            measure: choice.measure,
            gramsText: Formatters.fieldText(Self.defaultGrams)
        ))
    }
}
