import Foundation
import os
import SwiftData

/// Moves a recipe between its model and its draft. Writing replaces the ingredient rows
/// in draft order, freezing the draft's copy of each food, and saves once. Main-actor
/// because it drives a `ModelContext`.
struct RecipeWriter {
    let context: ModelContext

    /// A draft of an existing recipe, rows in their stored order.
    static func draft(of recipe: Recipe) -> RecipeDraft {
        var draft = RecipeDraft()
        draft.name = recipe.name
        draft.servings = recipe.servings
        draft.ingredients = recipe.sortedIngredients.map { row in
            IngredientDraft(
                id: row.id,
                source: row.food?.choice?.source,
                name: row.name,
                per100g: row.per100g,
                gramsText: Formatters.fieldText(row.grams)
            )
        }
        return draft
    }

    /// Creates the recipe when `existing` is `nil`, else updates it in place; logged
    /// entries keep their snapshots either way. Throws when the draft is not valid.
    func write(_ draft: RecipeDraft, into existing: Recipe?) throws {
        guard draft.isValid else { throw RecipeWriteError.invalidDraft }
        let recipe: Recipe
        if let existing {
            recipe = existing
            for row in existing.ingredients ?? [] {
                context.delete(row)
            }
        } else {
            recipe = Recipe(name: draft.trimmedName, servings: draft.servings)
            context.insert(recipe)
        }
        recipe.name = draft.trimmedName
        recipe.servings = draft.servings
        recipe.updatedAt = Date.now
        do {
            for (index, row) in draft.ingredients.enumerated() {
                guard let grams = row.grams else { throw RecipeWriteError.invalidDraft }
                let ingredient = RecipeIngredient(sortIndex: index, grams: grams, name: row.name, per100g: row.per100g)
                context.insert(ingredient)
                ingredient.recipe = recipe
                ingredient.food = try food(for: row)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        AppLog.store.info("saved recipe \(recipe.id.uuidString, privacy: .public) with \(draft.ingredients.count) rows")
    }

    /// The stored food to link for display. A bundled food gets its stored copy created
    /// on first use, without refreshing an existing one from the row's frozen values.
    private func food(for row: IngredientDraft) throws -> Food? {
        switch row.source {
        case .bundled(let id):
            let choice = FoodChoice(source: .bundled(id: id), name: row.name, perUnit: row.per100g)
            return try Food.storeBundled(choice, refresh: false, in: context)
        case .custom(let foodID):
            return try Food.custom(id: foodID, in: context)
        case .recipe, nil:
            return nil
        }
    }
}

nonisolated enum RecipeWriteError: Error, Equatable, Sendable, LocalizedError {
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "The recipe needs a name, at least one ingredient, and a gram amount on every row."
        }
    }
}
