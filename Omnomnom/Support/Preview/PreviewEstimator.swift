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

/// Fixed model answers and the drafts they become, matched and unmatched. The matched
/// draft carries its own database rows, so a preview shows real values whether or not
/// `foods.sqlite` has been built into the bundle on this Mac.
nonisolated enum PreviewEstimates {
    /// Two scrambled eggs, a slice of rye toast and butter, as the model would return
    /// them: a name to show, a term to search, and the weight eaten.
    static let breakfast = MealEstimate(
        items: [
            EstimatedItem(name: "Scrambled eggs", lookupTerm: "scrambled eggs", grams: 120),
            EstimatedItem(name: "Rye toast", lookupTerm: "rye bread", grams: 35),
            EstimatedItem(name: "Butter", lookupTerm: "butter, salted", grams: 8),
        ],
        note: "Assumed two medium eggs cooked in a little butter and one slice of rye toast."
    )

    /// `breakfast` with a food behind every row, as a resolved estimate looks.
    static let matchedDraft = draft(choices: [
        FoodChoice(bundled: scrambledEggs),
        FoodChoice(bundled: ryeBread),
        FoodChoice(bundled: butter),
    ])

    /// `breakfast` with nothing found, as every estimate looks when the database is not
    /// in the bundle, and as a single row looks until a food is chosen for it.
    static let unmatchedDraft = draft(choices: [nil, nil, nil])

    /// The converted items with the given foods attached, one per row in order.
    private static func draft(choices: [FoodChoice?]) -> EstimateDraft {
        let result = EstimateConversion.convert(breakfast)
        var items: [ResolvedEstimateItem] = []
        for (index, item) in result.items.enumerated() {
            let choice = index < choices.count ? choices[index] : nil
            items.append(ResolvedEstimateItem(id: item.id, name: item.name, grams: item.grams, choice: choice))
        }
        return EstimateDraft(note: result.note, items: items)
    }

    /// Database rows the preview stands in for, USDA figures rounded.
    private static let scrambledEggs = BundledFood(
        id: 9001, name: "Eggs, scrambled, cooked", category: "Dairy and Egg Products",
        per100g: Nutrition(energy: 149, protein: 10, carbohydrates: 1.6, fatTotal: 11, fatSaturated: 3.6, fiber: 0, sugar: 1.4, sodium: 145),
        popularity: 80
    )
    private static let ryeBread = BundledFood(
        id: 9002, name: "Bread, rye", category: "Baked Products",
        per100g: Nutrition(energy: 259, protein: 8.5, carbohydrates: 48.3, fatTotal: 3.3, fatSaturated: 0.6, fiber: 5.8, sugar: 3.9, sodium: 603),
        popularity: 70
    )
    private static let butter = BundledFood(
        id: 9003, name: "Butter, salted", category: "Dairy and Egg Products",
        per100g: Nutrition(energy: 717, protein: 0.9, carbohydrates: 0.1, fatTotal: 81.1, fatSaturated: 51.4, fiber: 0, sugar: 0.1, sodium: 643),
        popularity: 60
    )
}
#endif
