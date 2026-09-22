import Foundation
import os
import SwiftData

/// Why a choice from the Add sheet could not be logged.
nonisolated enum EntryLoggerError: Error, Equatable, Sendable, LocalizedError {
    /// The custom food or recipe was deleted while the sheet was open.
    case sourceMissing
    /// The recipe has no ingredient rows, so a serving weighs nothing.
    case emptyRecipe

    var errorDescription: String? {
        switch self {
        case .sourceMissing: "This item no longer exists."
        case .emptyRecipe: "This recipe has no ingredients."
        }
    }
}

extension EntryLogger {
    /// Logs what was picked in the Add sheet. `amount` is grams for a food and servings
    /// for a recipe. A bundled food's snapshot comes from the live choice and refreshes
    /// the stored copy; a custom food, a product and a recipe are read from their stored
    /// rows, so the entry reflects what the Library holds at this moment. `isEstimate`
    /// marks an entry the user confirmed from an on-device estimate: same food, same
    /// values, the badge on Today, and an amount that is counted as a use but never kept
    /// as the prefill, since nobody typed it.
    func log(
        choice: FoodChoice, amount: Double, mealSlot: MealSlot, at timestamp: Date, isEstimate: Bool = false
    ) async throws -> LogResult {
        switch choice.source {
        case .bundled:
            guard let food = try Food.storeBundled(choice, refresh: true, in: context) else {
                throw EntryLoggerError.sourceMissing
            }
            return try await insert(
                food: food, per100g: choice.perUnit, grams: amount, mealSlot: mealSlot, at: timestamp, isEstimate: isEstimate
            )
        case .custom(let foodID):
            guard let food = try Food.custom(id: foodID, in: context) else { throw EntryLoggerError.sourceMissing }
            return try await insert(
                food: food, per100g: food.per100g, grams: amount, mealSlot: mealSlot, at: timestamp, isEstimate: isEstimate
            )
        case .product(let foodID):
            guard let food = try Food.product(id: foodID, in: context) else { throw EntryLoggerError.sourceMissing }
            return try await insert(
                food: food, per100g: food.per100g, grams: amount, mealSlot: mealSlot, at: timestamp, isEstimate: isEstimate
            )
        case .recipe(let id):
            guard let recipe = try Recipe.find(id: id, in: context) else { throw EntryLoggerError.sourceMissing }
            return try await insert(
                recipe: recipe, servings: amount, mealSlot: mealSlot, at: timestamp, isEstimate: isEstimate
            )
        }
    }

    /// The local save is the part that throws; Health and the follow-up save report through the result.
    private func insert(
        food: Food, per100g: Nutrition, grams: Double, mealSlot: MealSlot, at timestamp: Date, isEstimate: Bool
    ) async throws -> LogResult {
        let entry = LogEntry(
            timestamp: timestamp,
            mealSlot: mealSlot,
            foodName: food.name,
            grams: grams,
            snapshot: SnapshotMath.snapshot(per100g: per100g, grams: grams)
        )
        context.insert(entry)
        entry.isEstimate = isEstimate
        entry.food = food
        let lastAmount = food.lastGrams
        food.noteUsed(grams: grams, at: Date.now)
        if isEstimate {
            // An estimated weight is the model's guess. It counts as a use, but it must
            // not come back as the amount the Quantity sheet prefills next time, which
            // would pass the guess off as something the user had typed.
            food.lastGrams = lastAmount
        }
        try context.save()
        AppLog.store.info("logged \(entry.id.uuidString, privacy: .public)")
        return await mirror(entry)
    }

    /// Freezes per-serving times `servings` into the entry, with the raw grams that
    /// many servings weigh, and links the recipe for display only.
    private func insert(
        recipe: Recipe, servings: Double, mealSlot: MealSlot, at timestamp: Date, isEstimate: Bool
    ) async throws -> LogResult {
        guard !recipe.sortedIngredients.isEmpty else { throw EntryLoggerError.emptyRecipe }
        let entry = LogEntry(
            timestamp: timestamp,
            mealSlot: mealSlot,
            foodName: recipe.name,
            grams: recipe.gramsPerServing * servings,
            snapshot: RecipeMath.snapshot(perServing: recipe.perServing, servings: servings)
        )
        context.insert(entry)
        entry.isEstimate = isEstimate
        entry.servings = servings
        entry.recipe = recipe
        let lastAmount = recipe.lastServings
        recipe.noteUsed(servings: servings, at: Date.now)
        if isEstimate {
            recipe.lastServings = lastAmount
        }
        try context.save()
        AppLog.store.info("logged \(entry.id.uuidString, privacy: .public) from recipe \(recipe.id.uuidString, privacy: .public)")
        return await mirror(entry)
    }
}
