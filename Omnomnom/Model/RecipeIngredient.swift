import Foundation
import SwiftData

/// One row of a recipe: a raw amount plus a frozen copy of the food's name, unit and
/// per-100 values taken when the row was added. The `food` link is display only,
/// so a deleted or refreshed food never changes what the recipe computes.
///
/// Same schema rules as the other models: defaulted scalars, optional relationships
/// with the inverses declared on `Recipe` and `Food`, and eight flat nutrient columns
/// packed by `per100g`. Order lives in `sortIndex`, never in the relationship.
@Model
final class RecipeIngredient {
    var id: UUID = UUID()
    var sortIndex: Int = 0
    /// The raw amount of this row, counted in `measure`'s unit.
    var grams: Double = 0
    /// Raw `FoodMeasure`, copied from the food when the row was added.
    var measureRaw: String = FoodMeasure.mass.rawValue
    /// Name at the time the row was added; never changes with the food.
    var name: String = ""
    var per100gEnergy: Double?
    var per100gProtein: Double?
    var per100gCarbohydrates: Double?
    var per100gFatTotal: Double?
    var per100gFatSaturated: Double?
    var per100gFiber: Double?
    var per100gSugar: Double?
    var per100gSodium: Double?
    var recipe: Recipe?
    var food: Food?

    /// Relate to a `Recipe` and a `Food` after `context.insert(ingredient)`, not here.
    init(sortIndex: Int, grams: Double, name: String, per100g: Nutrition, measure: FoodMeasure = .mass) {
        self.id = UUID()
        self.sortIndex = sortIndex
        self.grams = grams
        self.measureRaw = measure.rawValue
        self.name = name
        self.per100g = per100g
    }

    /// Grams or millilitres: the unit this row's amount and per-100 values are in.
    var measure: FoodMeasure {
        get { FoodMeasure(rawValue: measureRaw) ?? .mass }
        set { measureRaw = newValue.rawValue }
    }

    /// The frozen per-100 values as one value type, in `measure`'s unit.
    var per100g: Nutrition {
        get {
            Nutrition(
                energy: per100gEnergy, protein: per100gProtein, carbohydrates: per100gCarbohydrates,
                fatTotal: per100gFatTotal, fatSaturated: per100gFatSaturated, fiber: per100gFiber,
                sugar: per100gSugar, sodium: per100gSodium
            )
        }
        set {
            per100gEnergy = newValue.energy
            per100gProtein = newValue.protein
            per100gCarbohydrates = newValue.carbohydrates
            per100gFatTotal = newValue.fatTotal
            per100gFatSaturated = newValue.fatSaturated
            per100gFiber = newValue.fiber
            per100gSugar = newValue.sugar
            per100gSodium = newValue.sodium
        }
    }

    /// What this row adds to the recipe total.
    var contribution: Nutrition {
        per100g.scaled(toGrams: grams)
    }
}
