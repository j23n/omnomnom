import Foundation
import FoundationModels

/// What the on-device model returns for one meal: the foods it recognised, how much of
/// each was eaten, and one sentence on what it assumed. No nutrient values: those are a
/// lookup in the bundled database, not something a language model can know.
/// `nonisolated` so the estimator actor can hand it across; `Sendable` for the same reason.
@Generable(description: "The foods in one meal and how much of each was eaten, for a food log")
nonisolated struct MealEstimate: Sendable {
    @Guide(description: "Each distinct food or drink in the meal", .maximumCount(12))
    var items: [EstimatedItem]

    /// Which meal this was, from the food rather than from the clock.
    ///
    /// Someone describing their oats at nine in the evening means breakfast, and the clock
    /// cannot know that. `MealSlot.timestamp(on:)` then moves the recorded time to match
    /// the meal, so the label and the hour agree. The user sees both on the sheet and
    /// changes either before anything is logged.
    @Guide(description: "Which meal these foods belong to, judged from the foods themselves and not from the time of day")
    var meal: EstimatedMeal

    @Guide(description: "One short sentence on what was assumed, and whether the estimate is uncertain")
    var note: String

    init(items: [EstimatedItem], meal: EstimatedMeal = .snack, note: String) {
        self.items = items
        self.meal = meal
        self.note = note
    }
}

/// The meal the model judged these foods to belong to.
///
/// Its own type rather than `MealSlot`, so the app's stored enum is not a thing a model
/// can be asked to produce: this one exists to be generated and is mapped across once.
@Generable(description: "Which meal of the day a set of foods belongs to")
nonisolated enum EstimatedMeal: String, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var slot: MealSlot {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .snack: .snack
        }
    }
}

/// One food or drink in the estimate: what to call it, what to look it up as, and how
/// much of it was eaten. `name` is what the user sees; `lookupTerm` is what the database
/// search runs on. The range keeps the weight inside plausible bounds; `EstimateConversion`
/// clamps once more before anything is shown.
@Generable(description: "One food or drink and the weight of the portion eaten")
nonisolated struct EstimatedItem: Sendable {
    @Guide(description: "Short plain name of the food or drink, as the person who ate it would say it")
    var name: String

    @Guide(description: "The same food in the generic, unbranded wording a nutrition database uses: \"scrambled eggs\" for \"my scramble\", \"rye bread\" for \"dark toast\"")
    var lookupTerm: String

    @Guide(description: "Estimated weight eaten, in grams", .range(1...3000))
    var grams: Double

    init(name: String, lookupTerm: String, grams: Double) {
        self.name = name
        self.lookupTerm = lookupTerm
        self.grams = grams
    }
}
