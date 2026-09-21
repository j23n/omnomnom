import Foundation
import FoundationModels

/// What the on-device model returns for one meal: the items it recognised and one
/// sentence on what it assumed. Every number is for the portion eaten, never per 100 g.
/// `nonisolated` so the estimator actor can hand it across; `Sendable` for the same reason.
@Generable(description: "The estimated nutrition of one meal for a food log")
nonisolated struct MealEstimate: Sendable {
    @Guide(description: "Each distinct food or drink in the meal", .maximumCount(12))
    var items: [EstimatedItem]

    @Guide(description: "One short sentence on what was assumed, and whether the estimate is uncertain")
    var note: String

    init(items: [EstimatedItem], note: String) {
        self.items = items
        self.note = note
    }
}

/// One food or drink in the estimate. The ranges keep the model inside plausible
/// bounds; `EstimateConversion` clamps once more before anything is shown.
@Generable(description: "One food or drink and its nutrition for the portion eaten")
nonisolated struct EstimatedItem: Sendable {
    @Guide(description: "Short plain name of the food or drink")
    var name: String

    @Guide(description: "Estimated weight eaten, in grams", .range(1...3000))
    var grams: Double

    @Guide(description: "Energy in kcal for the estimated weight, not per 100 g", .range(0...5000))
    var kcal: Double

    @Guide(description: "Protein in grams for the estimated weight, not per 100 g", .range(0...1000))
    var proteinGrams: Double

    @Guide(description: "Carbohydrates in grams for the estimated weight, not per 100 g", .range(0...1000))
    var carbGrams: Double

    @Guide(description: "Total fat in grams for the estimated weight, not per 100 g", .range(0...1000))
    var fatGrams: Double

    @Guide(description: "Saturated fat in grams for the estimated weight, not per 100 g", .range(0...1000))
    var saturatedFatGrams: Double

    @Guide(description: "Fiber in grams for the estimated weight, not per 100 g", .range(0...1000))
    var fiberGrams: Double

    @Guide(description: "Sugar in grams for the estimated weight, not per 100 g", .range(0...1000))
    var sugarGrams: Double

    @Guide(description: "Sodium in milligrams for the estimated weight, not per 100 g", .range(0...20000))
    var sodiumMilligrams: Double

    init(
        name: String, grams: Double, kcal: Double, proteinGrams: Double, carbGrams: Double, fatGrams: Double,
        saturatedFatGrams: Double, fiberGrams: Double, sugarGrams: Double, sodiumMilligrams: Double
    ) {
        self.name = name
        self.grams = grams
        self.kcal = kcal
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.sodiumMilligrams = sodiumMilligrams
    }

    /// The eight values as the app's own type, unchecked.
    var nutrition: Nutrition {
        Nutrition(
            energy: kcal, protein: proteinGrams, carbohydrates: carbGrams, fatTotal: fatGrams,
            fatSaturated: saturatedFatGrams, fiber: fiberGrams, sugar: sugarGrams, sodium: sodiumMilligrams
        )
    }
}
