import Foundation

/// One item of the estimate before the database is searched: the name the user will see,
/// the wording to search for, and the weight eaten. It carries no nutrition, because the
/// model is never asked for any.
nonisolated struct EstimatedDraftItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The generic wording to search the bundled database with; may be empty, and then
    /// the name is searched instead.
    var lookupTerm: String
    var grams: Double

    init(id: UUID = UUID(), name: String, lookupTerm: String, grams: Double) {
        self.id = id
        self.name = name
        self.lookupTerm = lookupTerm
        self.grams = grams
    }
}

/// Turns what the model said into items to look up: names trimmed and capped, weights
/// clamped to what the amount field accepts, anything weightless dropped. Pure, tested.
nonisolated enum EstimateConversion {
    static let maximumNameLength = 100
    static let maximumNoteLength = 300
    static let fallbackName = "Unnamed food"

    /// The note and the items, in the order the model gave them.
    nonisolated struct Result: Hashable, Sendable {
        let note: String
        let items: [EstimatedDraftItem]
    }

    /// Drops items with no usable weight and caps the rest to the gram field's bounds.
    static func convert(_ estimate: MealEstimate) -> Result {
        var items: [EstimatedDraftItem] = []
        for raw in estimate.items {
            guard raw.grams.isFinite, raw.grams > 0 else { continue }
            let grams = min(max(raw.grams, Formatters.minimumAmount), Formatters.maximumAmount)
            items.append(
                EstimatedDraftItem(name: cleanName(raw.name), lookupTerm: cleanTerm(raw.lookupTerm), grams: grams)
            )
        }
        return Result(note: cleanNote(estimate.note), items: items)
    }

    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName }
        return String(trimmed.prefix(maximumNameLength))
    }

    /// The search term as the model wrote it, trimmed and capped. Unlike a name it may
    /// come back empty: a blank term is never searched, it falls back to the name.
    static func cleanTerm(_ term: String) -> String {
        String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
    }

    static func cleanNote(_ note: String) -> String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNoteLength))
    }

    /// Sum of the matched rows, from their food's values. Every nutrient reads 0 rather
    /// than blank; a row without a food contributes nothing.
    static func totals(of items: [ResolvedEstimateItem]) -> Nutrition {
        SnapshotMath.total(of: items.compactMap(\.nutrition))
    }
}
