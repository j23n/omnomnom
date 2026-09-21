import Foundation
import SwiftData

/// Origin of a `Food` row: a bundled database reference, a food the user created in
/// the Library, or a packaged product identified by its barcode.
nonisolated enum FoodKind: String, Codable, Sendable {
    case bundled
    case custom
    case product
}

/// Where a product row's values came from: fetched from Open Food Facts, or typed
/// from the label after a miss. Bundled and custom foods carry no source.
nonisolated enum FoodSource: String, Codable, Sendable {
    case openFoodFacts = "off"
    case manual
}

/// A food the user has logged or put in a recipe: a reference into the bundled database
/// plus the per-100 g values copied at that time, a custom food whose values live
/// here alone, or a cached product, and the usage data that drives recents.
///
/// Schema rules for a later CloudKit retrofit: no unique attributes, every attribute
/// optional or defaulted, relationships optional with explicit inverses. The eight
/// nutrients are flat optional scalars; `per100g` packs them into a `Nutrition`.
@Model
final class Food {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = FoodKind.bundled.rawValue
    var bundledID: Int?
    var per100gEnergy: Double?
    var per100gProtein: Double?
    var per100gCarbohydrates: Double?
    var per100gFatTotal: Double?
    var per100gFatSaturated: Double?
    var per100gFiber: Double?
    var per100gSugar: Double?
    var per100gSodium: Double?
    var lastGrams: Double?
    var lastUsed: Date?
    var useCount: Int = 0
    /// The normalised barcode a product row caches; `nil` for the other kinds.
    var barcode: String?
    var brand: String?
    /// Raw `FoodSource` of a product row.
    var sourceRaw: String?
    /// When the values were fetched from Open Food Facts; `nil` for typed values.
    var fetchedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.food)
    var entries: [LogEntry]?

    /// Recipe rows that were added from this food; each keeps its own frozen copy.
    @Relationship(deleteRule: .nullify, inverse: \RecipeIngredient.food)
    var ingredientUses: [RecipeIngredient]?

    init(name: String, kind: FoodKind, bundledID: Int?, per100g: Nutrition) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.bundledID = bundledID
        self.useCount = 0
        self.per100g = per100g
    }

    var kind: FoodKind {
        get { FoodKind(rawValue: kindRaw) ?? .bundled }
        set { kindRaw = newValue.rawValue }
    }

    var source: FoodSource? {
        get { sourceRaw.flatMap(FoodSource.init(rawValue:)) }
        set { sourceRaw = newValue?.rawValue }
    }

    /// The eight per-100 g values as one value type.
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

    /// Records a use for recents and the prefilled gram amount.
    func noteUsed(grams: Double, at date: Date) {
        lastGrams = grams
        lastUsed = date
        useCount += 1
    }

    /// The choice to reopen this food in the Quantity sheet; `nil` for a bundled
    /// reference without its id or a product row without its barcode.
    var choice: FoodChoice? {
        switch kind {
        case .bundled:
            guard let bundledID else { return nil }
            return FoodChoice(source: .bundled(id: bundledID), name: name, perUnit: per100g, lastAmount: lastGrams)
        case .custom:
            return FoodChoice(source: .custom(foodID: id), name: name, perUnit: per100g, lastAmount: lastGrams)
        case .product:
            guard let barcode else { return nil }
            let attribution = ProductAttribution(barcode: barcode, brand: brand, source: source ?? .manual)
            return FoodChoice(
                source: .product(foodID: id), name: name, perUnit: per100g,
                lastAmount: lastGrams, attribution: attribution
            )
        }
    }
}
