#if DEBUG
import Foundation

/// An estimator for previews: waits a moment, then answers with a fixed breakfast.
/// Never creates a language model session.
nonisolated struct PreviewMealEstimator: MealEstimating {
    var delay: Duration = .seconds(2)

    func estimate(_ input: EstimationInput) async throws -> MealEstimate {
        try await Task.sleep(for: delay)
        return PreviewEstimates.breakfast
    }
}

/// Fixed model answers and the draft they convert to.
nonisolated enum PreviewEstimates {
    /// Two scrambled eggs, a slice of rye toast and butter, as the model would return them.
    static let breakfast = MealEstimate(
        items: [
            EstimatedItem(
                name: "Scrambled eggs", grams: 120, kcal: 200, proteinGrams: 13.5, carbGrams: 2, fatGrams: 15,
                saturatedFatGrams: 5.2, fiberGrams: 0, sugarGrams: 1.2, sodiumMilligrams: 320
            ),
            EstimatedItem(
                name: "Rye toast", grams: 35, kcal: 90, proteinGrams: 3, carbGrams: 17, fatGrams: 1.2,
                saturatedFatGrams: 0.2, fiberGrams: 2.3, sugarGrams: 1.5, sodiumMilligrams: 200
            ),
            EstimatedItem(
                name: "Butter", grams: 8, kcal: 0, proteinGrams: 0.1, carbGrams: 0, fatGrams: 6.5,
                saturatedFatGrams: 4.1, fiberGrams: 0, sugarGrams: 0, sodiumMilligrams: 50
            ),
        ],
        note: "Assumed two medium eggs cooked in a little butter and one slice of rye toast."
    )

    /// `breakfast` after conversion: the butter's energy is computed from its macros, with a warning.
    static let draft = EstimateDraft(result: EstimateConversion.convert(breakfast))
}
#endif
