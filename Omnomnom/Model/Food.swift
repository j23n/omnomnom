import Foundation
import SwiftData

/// Origin of a `Food` row. Only `bundled` is created in this version; the other
/// cases are reserved so adding custom foods and products is additive.
nonisolated enum FoodKind: String, Codable, Sendable {
    case bundled
    case custom
    case product
}

/// A food the user has logged at least once: a reference into the bundled database
/// plus the per-100 g values copied at that time and the usage data that drives recents.
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

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.food)
    var entries: [LogEntry]?

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

    /// The choice to reopen this food in the Quantity sheet; `nil` for a food without a bundled row.
    var choice: FoodChoice? {
        guard let bundledID else { return nil }
        return FoodChoice(bundledID: bundledID, name: name, per100g: per100g, lastGrams: lastGrams)
    }

    /// The stored row for a bundled food, if it was ever logged. Shared by the Add sheet and the logger.
    static func bundled(id: Int, in context: ModelContext) throws -> Food? {
        let bundledID: Int? = id
        var descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.bundledID == bundledID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
