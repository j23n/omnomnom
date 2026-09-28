import Foundation

/// Turning an estimate into a recipe the user keeps.
///
/// An estimate and a recipe are the same shape once the rows are matched: a list of
/// foods with an amount each. So a meal worth estimating twice is worth keeping, and
/// keeping it means never estimating it again.
extension EstimateDraft {
    /// The rows as a recipe draft, ready for the recipe editor to name and divide.
    ///
    /// A row without a food is left out: a recipe row carries values, and an unmatched
    /// row has none. Servings start at one, because an estimate is one plate of food;
    /// the editor is where that becomes four.
    func recipeDraft(named name: String, photo: Data? = nil) -> RecipeDraft {
        var recipe = RecipeDraft()
        recipe.name = name
        recipe.servings = 1
        recipe.photo = photo
        recipe.ingredients = rows.compactMap { row in
            guard let choice = row.choice, !choice.isRecipe else { return nil }
            return IngredientDraft(
                id: row.id,
                source: choice.source,
                name: choice.name,
                per100g: choice.perUnit,
                measure: choice.measure,
                amountText: row.amountText
            )
        }
        return recipe
    }

    /// Whether there is anything to keep: at least one row with a food behind it.
    var canBecomeRecipe: Bool {
        rows.contains { $0.choice?.isRecipe == false }
    }
}
