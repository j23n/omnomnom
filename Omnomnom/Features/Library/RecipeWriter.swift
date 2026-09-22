import Foundation
import os
import SwiftData

/// Moves a recipe between its model and its draft. Writing replaces the ingredient rows
/// in draft order, freezing the draft's copy of each food and the unit it is measured
/// in, creates, replaces or deletes the photo, and saves once. Main-actor because it
/// drives a `ModelContext`.
struct RecipeWriter {
    let context: ModelContext

    /// A draft of an existing recipe, rows in their stored order.
    static func draft(of recipe: Recipe) -> RecipeDraft {
        var draft = RecipeDraft()
        draft.name = recipe.name
        draft.servings = recipe.servings
        draft.photo = recipe.photo?.data
        draft.ingredients = recipe.sortedIngredients.map { row in
            IngredientDraft(
                id: row.id,
                source: row.food?.choice?.source,
                name: row.name,
                per100g: row.per100g,
                measure: row.measure,
                amountText: Formatters.fieldText(row.grams)
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
        recipe.photo = Photo.replacing(recipe.photo, with: draft.photo, in: context)
        do {
            for (index, row) in draft.ingredients.enumerated() {
                guard let amount = row.amount else { throw RecipeWriteError.invalidDraft }
                let ingredient = RecipeIngredient(
                    sortIndex: index, amount: amount, name: row.name, per100g: row.per100g, measure: row.measure
                )
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
            // The bundled database is per 100 g throughout, so a row that came from it
            // is a mass whatever the draft carries; the stored copy must say so.
            let choice = FoodChoice(source: .bundled(id: id), name: row.name, perUnit: row.per100g, measure: .mass)
            return try Food.storeBundled(choice, refresh: false, in: context)
        case .custom(let foodID):
            return try Food.custom(id: foodID, in: context)
        case .product(let foodID):
            return try Food.product(id: foodID, in: context)
        case .recipe, nil:
            return nil
        }
    }
}

nonisolated enum RecipeWriteError: Error, Equatable, Sendable, LocalizedError {
    case invalidDraft

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "The recipe needs a name, at least one ingredient, and an amount on every row."
        }
    }
}
