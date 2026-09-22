import Foundation

/// How an already logged entry's amount scales, read out of the entry itself.
///
/// The snapshot on a `LogEntry` is frozen, so correcting the amount scales that
/// snapshot rather than reading the linked food's current values: an entry is a record
/// of what was logged, not a live reference. Repeating an entry deliberately does the
/// opposite and re-reads a custom food, because that is a new log. Scaling the entry
/// gives one code path for foods, recipes, estimates and entries whose food or recipe
/// has since been deleted.
nonisolated struct EntryAmountBasis: Hashable, Sendable {
    /// The entry seen as a choice, so the editor can reuse the amount field, the chips
    /// and the nutrition preview the Quantity sheet is built from, and so the scaling
    /// has a single implementation. Built once, since it carries the entry's photo.
    /// The source points at the linked recipe or food where there still is one and at
    /// the entry itself otherwise: it only has to be stable while the sheet is open.
    let choice: FoodChoice
    /// The amount the entry holds now: its own grams or millilitres, or its servings.
    let amount: Double

    /// Whether the amount is counted in servings rather than in the food's own unit.
    var isServings: Bool { choice.isRecipe }

    /// `nil` when there is nothing to scale: no grams, or a servings count of zero or
    /// less, where a per-unit value would be an infinity. The editor still lets such an
    /// entry move to another meal or time.
    @MainActor
    init?(entry: LogEntry) {
        guard entry.grams > 0 else { return nil }
        let perUnit: Nutrition
        let gramsPerServing: Double?
        if let servings = entry.servings {
            guard servings > 0 else { return nil }
            perUnit = RecipeMath.perServing(total: entry.snapshot, servings: servings)
            gramsPerServing = RecipeMath.gramsPerServing(weight: entry.grams, servings: servings)
            amount = servings
        } else {
            // The inverse of `SnapshotMath.snapshot(per100g:grams:)`, which froze the snapshot.
            let grams = entry.grams
            perUnit = entry.snapshot.map { $0 * 100 / grams }
            gramsPerServing = nil
            amount = grams
        }
        let attribution = entry.food.flatMap { food in
            food.barcode.map { ProductAttribution(barcode: $0, brand: food.brand, source: food.source ?? .manual) }
        }
        choice = FoodChoice(
            source: gramsPerServing == nil
                ? .custom(foodID: entry.food?.id ?? entry.id)
                : .recipe(id: entry.recipe?.id ?? entry.id),
            name: entry.foodName,
            perUnit: perUnit,
            measure: entry.measure,
            gramsPerServing: gramsPerServing,
            lastAmount: nil,
            attribution: attribution,
            photo: entry.displayPhoto?.data
        )
    }

    /// Raw grams for `amount` units, as the choice counts them.
    func grams(for amount: Double) -> Double {
        choice.grams(for: amount)
    }

    /// The nutrition to freeze for `amount` units, as the choice scales it.
    func snapshot(for amount: Double) -> Nutrition {
        choice.snapshot(for: amount)
    }
}
