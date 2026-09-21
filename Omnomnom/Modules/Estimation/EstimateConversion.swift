import Foundation

/// One row of the draft the user confirms: the values are the entry's snapshot as is.
nonisolated struct EstimatedDraftItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var grams: Double
    var nutrition: Nutrition

    init(id: UUID = UUID(), name: String, grams: Double, nutrition: Nutrition) {
        self.id = id
        self.name = name
        self.grams = grams
        self.nutrition = nutrition
    }
}

/// Turns what the model said into draft rows with plausibility clamps, so nothing the
/// model invents can reach the store or Health unbounded. Pure, tested.
nonisolated enum EstimateConversion {
    static let maximumNameLength = 100
    static let maximumNoteLength = 300
    static let fallbackName = "Unnamed food"

    /// The note, then a warning per item whose energy had to be computed from its macros.
    nonisolated struct Result: Hashable, Sendable {
        let note: String
        let warnings: [String]
        let items: [EstimatedDraftItem]
    }

    /// Drops items with no weight or negative energy, caps every value, computes energy
    /// from the macros when the model left it at 0 but filled them in.
    static func convert(_ estimate: MealEstimate) -> Result {
        var items: [EstimatedDraftItem] = []
        var warnings: [String] = []
        for raw in estimate.items {
            guard raw.grams.isFinite, raw.grams > 0, raw.kcal.isFinite, raw.kcal >= 0 else { continue }
            let name = cleanName(raw.name)
            var nutrition = raw.nutrition.map(clamp)
            if nutrition.energy == 0, let computed = energyFromMacros(nutrition), computed > 0 {
                nutrition.energy = clamp(computed)
                warnings.append("Energy for \(name) was computed from its macros.")
            }
            let grams = min(max(raw.grams, Formatters.minimumGrams), Formatters.maximumGrams)
            items.append(EstimatedDraftItem(name: name, grams: grams, nutrition: nutrition))
        }
        return Result(note: cleanNote(estimate.note), warnings: warnings, items: items)
    }

    /// Non-finite or negative becomes 0; anything above the manual-entry bound is capped there.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), Formatters.maximumNutrientValue)
    }

    /// 4 kcal per gram of protein and carbohydrate, 9 per gram of fat; `nil` when all three are absent.
    static func energyFromMacros(_ nutrition: Nutrition) -> Double? {
        guard nutrition.protein != nil || nutrition.carbohydrates != nil || nutrition.fatTotal != nil else { return nil }
        return 4 * (nutrition.protein ?? 0) + 4 * (nutrition.carbohydrates ?? 0) + 9 * (nutrition.fatTotal ?? 0)
    }

    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName }
        return String(trimmed.prefix(maximumNameLength))
    }

    static func cleanNote(_ note: String) -> String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNoteLength))
    }

    /// Sum of the rows; every nutrient reads 0 rather than blank.
    static func totals(of items: [EstimatedDraftItem]) -> Nutrition {
        SnapshotMath.total(of: items.map(\.nutrition))
    }
}
