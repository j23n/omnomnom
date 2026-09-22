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

    /// `nil` when there is nothing to scale: no amount at all, an amount that is not in
    /// the unit the entry was logged in, or a servings count of zero or less, where a
    /// per-unit value would be an infinity. The editor still lets such an entry move to
    /// another meal or time.
    @MainActor
    init?(entry: LogEntry) {
        let logged = entry.rawAmount
        guard !logged.isEmpty else { return nil }
        let perUnit: Nutrition
        let amountPerServing: RawAmount?
        if let servings = entry.servings {
            guard servings > 0 else { return nil }
            perUnit = RecipeMath.perServing(total: entry.snapshot, servings: servings)
            amountPerServing = RecipeMath.amountPerServing(total: logged, servings: servings)
            amount = servings
        } else {
            // The inverse of `SnapshotMath.snapshot(per100g:grams:)`, which froze the
            // snapshot against the amount counted in the entry's own unit.
            let counted = logged.amount(in: entry.measure)
            guard counted > 0 else { return nil }
            perUnit = entry.snapshot.map { $0 * 100 / counted }
            amountPerServing = nil
            amount = counted
        }
        let attribution = entry.food.flatMap { food in
            food.barcode.map { ProductAttribution(barcode: $0, brand: food.brand, source: food.source ?? .manual) }
        }
        choice = FoodChoice(
            source: amountPerServing == nil
                ? .custom(foodID: entry.food?.id ?? entry.id)
                : .recipe(id: entry.recipe?.id ?? entry.id),
            name: entry.foodName,
            perUnit: perUnit,
            measure: entry.measure,
            amountPerServing: amountPerServing,
            lastAmount: nil,
            attribution: attribution,
            photo: entry.displayPhoto?.data
        )
    }

    /// The raw amount for `amount` units, as the choice counts it.
    func rawAmount(for amount: Double) -> RawAmount {
        choice.rawAmount(for: amount)
    }

    /// The nutrition to freeze for `amount` units, as the choice scales it.
    func snapshot(for amount: Double) -> Nutrition {
        choice.snapshot(for: amount)
    }
}
