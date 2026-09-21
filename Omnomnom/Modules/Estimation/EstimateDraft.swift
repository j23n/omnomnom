import Foundation

/// Editable state of one draft row: the name, the grams and one text per nutrient,
/// all as typed. A blank nutrient means unknown; text that does not parse blocks logging.
nonisolated struct EstimateDraftRow: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var gramsText: String
    private var fields: [Nutrient: String] = [:]

    init(item: EstimatedDraftItem) {
        id = item.id
        name = item.name
        gramsText = Formatters.fieldText(item.grams)
        for nutrient in Nutrient.allCases {
            if let value = item.nutrition[nutrient] {
                fields[nutrient] = Formatters.fieldText(value)
            }
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func text(for nutrient: Nutrient) -> String {
        fields[nutrient] ?? ""
    }

    mutating func setText(_ text: String, for nutrient: Nutrient) {
        fields[nutrient] = text
    }

    /// The typed grams within the amount field's bounds, or `nil`.
    var grams: Double? {
        Formatters.parseGrams(gramsText)
    }

    var isGramsInvalid: Bool {
        grams == nil
    }

    /// Whether a field holds text that does not parse; blank is fine.
    func isInvalid(_ nutrient: Nutrient) -> Bool {
        let text = self.text(for: nutrient).trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && Formatters.parseNutrientValue(text) == nil
    }

    /// The row as an item to log, or `nil` when the name is blank, the grams are out of
    /// range, or a field does not parse. Values are the snapshot as typed, not per 100 g.
    var item: EstimatedDraftItem? {
        guard !trimmedName.isEmpty, let grams else { return nil }
        var nutrition = Nutrition()
        for nutrient in Nutrient.allCases {
            let text = self.text(for: nutrient).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard let value = Formatters.parseNutrientValue(text) else { return nil }
            nutrition[nutrient] = value
        }
        return EstimatedDraftItem(id: id, name: String(trimmedName.prefix(EstimateConversion.maximumNameLength)), grams: grams, nutrition: nutrition)
    }
}

/// The whole draft the user confirms: the model's note, the conversion warnings, and
/// the rows. Pure value type so the maths behind the totals and the Log button is tested.
nonisolated struct EstimateDraft: Hashable, Sendable {
    var note: String
    var warnings: [String]
    var rows: [EstimateDraftRow]

    init(result: EstimateConversion.Result) {
        note = result.note
        warnings = result.warnings
        rows = result.items.map(EstimateDraftRow.init(item:))
    }

    /// Every row as an item, or `nil` when there are none or one of them is invalid.
    var items: [EstimatedDraftItem]? {
        guard !rows.isEmpty else { return nil }
        var items: [EstimatedDraftItem] = []
        for row in rows {
            guard let item = row.item else { return nil }
            items.append(item)
        }
        return items
    }

    /// Sum over the rows that parse; every nutrient reads 0 rather than blank.
    var totals: Nutrition {
        EstimateConversion.totals(of: rows.compactMap(\.item))
    }

    mutating func remove(id: UUID) {
        rows.removeAll { $0.id == id }
    }
}
