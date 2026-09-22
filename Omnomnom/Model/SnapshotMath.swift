import Foundation

/// Pure arithmetic behind the frozen snapshot on `LogEntry` and the totals on Today.
/// No SwiftData, so it is tested directly.
nonisolated enum SnapshotMath {
    /// The nutrition to freeze when logging `grams` of a food with `per100g` values.
    /// Both are counted in the food's own unit, so a food measured in millilitres goes
    /// through the same arithmetic with nothing converted.
    static func snapshot(per100g: Nutrition, grams: Double) -> Nutrition {
        per100g.scaled(toGrams: grams)
    }

    /// Sum of the given snapshots. Every nutrient reads 0 rather than blank when nothing contributes.
    static func total(of snapshots: [Nutrition]) -> Nutrition {
        snapshots.reduce(Nutrition.zero, +)
    }
}
