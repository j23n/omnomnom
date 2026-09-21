import Foundation

/// What the user picked in the Add sheet, reduced to values the Quantity sheet needs.
/// Only bundled foods exist in this version; custom foods and products extend this seam.
nonisolated struct FoodChoice: Identifiable, Hashable, Sendable {
    let bundledID: Int
    let name: String
    let per100g: Nutrition
    /// Grams used last time, to prefill the field. `nil` for a food never logged.
    let lastGrams: Double?

    var id: Int { bundledID }

    init(bundledID: Int, name: String, per100g: Nutrition, lastGrams: Double?) {
        self.bundledID = bundledID
        self.name = name
        self.per100g = per100g
        self.lastGrams = lastGrams
    }

    init(bundled: BundledFood) {
        self.init(bundledID: bundled.id, name: bundled.name, per100g: bundled.per100g, lastGrams: nil)
    }

    /// The same choice with the amount used last time filled in.
    func with(lastGrams: Double?) -> FoodChoice {
        FoodChoice(bundledID: bundledID, name: name, per100g: per100g, lastGrams: lastGrams)
    }
}
