import Foundation

/// Editable state of one draft row: the name the model gave, the food its values come
/// from, and the portion as typed, in that food's own unit. No nutrient is ever typed
/// here; the numbers are the database's, for the portion in the field.
nonisolated struct EstimateDraftRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    var amountText: String
    /// The food every value on this row comes from; `nil` until one is chosen.
    var choice: FoodChoice?

    init(item: ResolvedEstimateItem) {
        id = item.id
        name = item.name
        amountText = Formatters.fieldText(item.grams)
        choice = item.choice
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The typed portion within the amount field's bounds, or `nil`.
    var amount: Double? {
        Formatters.parseAmount(amountText)
    }

    /// The unit the portion is counted in: the matched food's own, grams until one is
    /// matched. The model always estimates a weight and every first match is a bundled
    /// food, which is per 100 g; only a food the user picks themselves can be a volume.
    var measure: FoodMeasure {
        choice?.measure ?? .mass
    }

    var isAmountInvalid: Bool {
        amount == nil
    }

    /// What this portion holds, from the matched food; `nil` until a food is chosen and
    /// the portion parses.
    var nutrition: Nutrition? {
        item?.nutrition
    }

    /// The row as an item to log, or `nil` when no food is matched or the portion is out
    /// of range. The values are derived from the food, never from what the model said.
    var item: ResolvedEstimateItem? {
        guard let choice, let amount else { return nil }
        return ResolvedEstimateItem(id: id, name: name, grams: amount, choice: choice)
    }
}

/// The whole draft the user confirms: the model's note and the rows. Pure value type so
/// the maths behind the totals and the Log button is tested.
nonisolated struct EstimateDraft: Hashable, Sendable {
    var note: String
    var rows: [EstimateDraftRow]

    init(note: String, items: [ResolvedEstimateItem]) {
        self.note = note
        rows = items.map(EstimateDraftRow.init(item:))
    }

    /// Every row as an item, or `nil` when there are none or one of them has no food or
    /// no usable weight.
    var items: [ResolvedEstimateItem]? {
        guard !rows.isEmpty else { return nil }
        var items: [ResolvedEstimateItem] = []
        for row in rows {
            guard let item = row.item else { return nil }
            items.append(item)
        }
        return items
    }

    /// Whether a row is still without a food. Such a row cannot be logged: there would be
    /// no values to log but invented ones.
    var hasUnmatchedRows: Bool {
        rows.contains { $0.choice == nil }
    }

    /// Sum over the rows that resolve; every nutrient reads 0 rather than blank.
    var totals: Nutrition {
        EstimateConversion.totals(of: rows.compactMap(\.item))
    }

    mutating func remove(id: UUID) {
        rows.removeAll { $0.id == id }
    }
}
