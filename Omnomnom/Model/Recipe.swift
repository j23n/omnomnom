import Foundation
import SwiftData

/// A named list of raw ingredient weights divided into servings. A template, not a
/// live reference: logging one freezes the per-serving figures into the entry, so
/// editing the recipe later never touches what was already logged or sent to Health.
///
/// Schema rules as for `Food`: no unique attributes, every attribute defaulted or
/// optional, relationships optional with the inverses declared here.
@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    /// Portions the raw total is divided into; always greater than 0.
    var servings: Double = 1
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Servings logged last time, to prefill the field. `nil` until first logged.
    var lastServings: Double?
    var lastUsed: Date?
    var useCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]?

    /// Entries logged from this recipe, for display only; their snapshots stand alone.
    @Relationship(deleteRule: .nullify, inverse: \LogEntry.recipe)
    var entries: [LogEntry]?

    init(name: String, servings: Double) {
        self.id = UUID()
        self.name = name
        self.servings = servings
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.useCount = 0
    }

    /// Ingredient rows in the order the user arranged them.
    var sortedIngredients: [RecipeIngredient] {
        (ingredients ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Raw weight and nutrition of the whole dish.
    var total: (weight: Double, nutrition: Nutrition) {
        RecipeMath.total(ingredients: sortedIngredients.map { (grams: $0.grams, per100g: $0.per100g) })
    }

    var perServing: Nutrition {
        RecipeMath.perServing(total: total.nutrition, servings: servings)
    }

    /// Raw grams in one serving.
    var gramsPerServing: Double {
        RecipeMath.gramsPerServing(weight: total.weight, servings: servings)
    }

    /// The choice that opens this recipe in the Quantity sheet, with per-serving values.
    var choice: FoodChoice {
        FoodChoice(
            source: .recipe(id: id),
            name: name,
            perUnit: perServing,
            gramsPerServing: gramsPerServing,
            lastAmount: lastServings
        )
    }

    /// Records a use for recents and the prefilled servings.
    func noteUsed(servings: Double, at date: Date) {
        lastServings = servings
        lastUsed = date
        useCount += 1
    }

    /// The stored recipe with this identifier, if it still exists.
    static func find(id: UUID, in context: ModelContext) throws -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Recipes whose name contains `text`, by name, for the Add sheet's "Yours" results.
    static func matching(_ text: String, in context: ModelContext) throws -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { $0.name.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\Recipe.name)]
        )
        return try context.fetch(descriptor)
    }
}
