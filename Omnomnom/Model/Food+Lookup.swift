import Foundation
import SwiftData

/// Fetches shared by the Add sheet, the logger, the recipe builder and the barcode flow.
extension Food {
    /// The stored row for a bundled food, if it was ever logged or used in a recipe.
    /// Filters on the kind too, so a custom food can never answer for a bundled id.
    static func bundled(id: Int, in context: ModelContext) throws -> Food? {
        let bundledID: Int? = id
        let kind = FoodKind.bundled.rawValue
        var descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.bundledID == bundledID && $0.kindRaw == kind }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The custom food with this identifier, if it still exists.
    static func custom(id: UUID, in context: ModelContext) throws -> Food? {
        try find(id: id, kind: .custom, in: context)
    }

    /// The product row with this identifier, if it still exists.
    static func product(id: UUID, in context: ModelContext) throws -> Food? {
        try find(id: id, kind: .product, in: context)
    }

    /// The cached product for a normalised barcode, fetched or typed; `nil` when the
    /// code was never resolved on this device.
    static func product(barcode code: String, in context: ModelContext) throws -> Food? {
        let barcode: String? = code
        let kind = FoodKind.product.rawValue
        var descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.barcode == barcode && $0.kindRaw == kind }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The stored copy of a bundled food, created on first use. With `refresh`, an
    /// existing row takes the live name and values from `choice`; without it the row
    /// is left as is, which suits a recipe row that carries its own frozen copy.
    static func storeBundled(_ choice: FoodChoice, refresh: Bool, in context: ModelContext) throws -> Food? {
        guard let bundledID = choice.bundledID else { return nil }
        if let existing = try bundled(id: bundledID, in: context) {
            if refresh, existing.name != choice.name || existing.per100g != choice.perUnit {
                existing.name = choice.name
                existing.per100g = choice.perUnit
            }
            return existing
        }
        let food = Food(
            name: choice.name, kind: .bundled, bundledID: bundledID,
            per100g: choice.perUnit, measure: choice.measure
        )
        context.insert(food)
        return food
    }

    /// Custom foods and cached products whose name contains `text`, for the Add
    /// sheet's "Yours" results.
    static func libraryMatching(_ text: String, in context: ModelContext) throws -> [Food] {
        let custom = FoodKind.custom.rawValue
        let product = FoodKind.product.rawValue
        let descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> {
                ($0.kindRaw == custom || $0.kindRaw == product) && $0.name.localizedStandardContains(text)
            },
            sortBy: [SortDescriptor(\Food.name)]
        )
        return try context.fetch(descriptor)
    }

    private static func find(id: UUID, kind: FoodKind, in context: ModelContext) throws -> Food? {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<Food>(
            predicate: #Predicate<Food> { $0.id == id && $0.kindRaw == kindRaw }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
