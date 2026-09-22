import Foundation
import Testing
@testable import Omnomnom

/// Editing an entry scales the entry's own frozen snapshot, so the basis read out of an
/// entry must round-trip: the amount it opened with reproduces the snapshot it was
/// frozen with, to within the rounding of a divide followed by a multiply.
struct EntryAmountBasisTests {
    private let per100g = Nutrition(energy: 165, protein: 31, fatTotal: 3.6, sodium: 74)

    private func gramEntry(grams: Double) -> LogEntry {
        LogEntry(
            timestamp: .now, mealSlot: .lunch, foodName: "Chicken breast", grams: grams,
            snapshot: SnapshotMath.snapshot(per100g: per100g, grams: grams)
        )
    }

    @Test func gramEntryRoundTripsAndScales() throws {
        let entry = gramEntry(grams: 150)
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings == false)
        #expect(basis.amount == 150)
        #expect(basis.choice.isRecipe == false)
        #expect(basis.choice.name == "Chicken breast")
        #expect(basis.choice.lastAmount == nil)
        #expect(nearly(basis.snapshot(for: 150), entry.snapshot))
        #expect(nearly(basis.snapshot(for: 300), entry.snapshot.map { $0 * 2 }))
        #expect(basis.grams(for: 300) == 300)
        #expect(nearly(basis.choice.snapshot(for: 150), basis.snapshot(for: 150)))
    }

    @Test func recipeEntryRoundTripsInServings() throws {
        let perServing = Nutrition(energy: 318, protein: 17.6, carbohydrates: 49.1, fiber: 9.9)
        let entry = LogEntry(
            timestamp: .now, mealSlot: .dinner, foodName: "Lentil soup", grams: 450,
            snapshot: RecipeMath.snapshot(perServing: perServing, servings: 1.5)
        )
        entry.servings = 1.5
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings)
        #expect(basis.amount == 1.5)
        #expect(basis.choice.isRecipe)
        #expect(basis.choice.gramsPerServing == 300)
        #expect(nearly(basis.snapshot(for: 1.5), entry.snapshot))
        #expect(nearly(basis.choice.perUnit, perServing))
        #expect(basis.grams(for: 2) == 600)
        #expect(basis.choice.grams(for: 2) == 600)
    }

    @Test func nothingToScaleWithoutAnAmount() {
        #expect(EntryAmountBasis(entry: gramEntry(grams: 0)) == nil)
        #expect(EntryAmountBasis(entry: gramEntry(grams: -20)) == nil)

        let noServings = gramEntry(grams: 150)
        noServings.servings = 0
        #expect(EntryAmountBasis(entry: noServings) == nil)
        noServings.servings = -1
        #expect(EntryAmountBasis(entry: noServings) == nil)
    }

    /// An estimate has no food and no recipe; it is measured in grams like any other entry.
    @Test func estimateBehavesLikeAGramEntry() throws {
        let portion = Nutrition(energy: 180, protein: 9.4, carbohydrates: 14.2, fatTotal: 9.6)
        let entry = LogEntry(timestamp: .now, mealSlot: .snack, foodName: "Latte", grams: 250, snapshot: portion)
        entry.isEstimate = true
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings == false)
        #expect(basis.amount == 250)
        #expect(basis.choice.attribution == nil)
        #expect(basis.choice.source == .custom(foodID: entry.id))
        #expect(nearly(basis.snapshot(for: 250), portion))
        #expect(nearly(basis.snapshot(for: 125), portion.map { $0 / 2 }))
        #expect(basis.grams(for: 125) == 125)
    }

    /// Nutrition equality after a divide and a multiply needs a tolerance per nutrient.
    private func nearly(_ lhs: Nutrition, _ rhs: Nutrition) -> Bool {
        Nutrient.allCases.allSatisfy { nutrient in
            switch (lhs[nutrient], rhs[nutrient]) {
            case (nil, nil): true
            case let (value?, other?): abs(value - other) < 0.0001
            default: false
            }
        }
    }
}
