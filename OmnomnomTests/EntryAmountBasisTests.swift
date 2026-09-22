import Foundation
import Testing
@testable import Omnomnom

/// Editing an entry scales the entry's own frozen snapshot, so the basis read out of an
/// entry must round-trip: the amount it opened with reproduces the snapshot it was
/// frozen with, to within the rounding of a divide followed by a multiply.
struct EntryAmountBasisTests {
    private let per100 = Nutrition(energy: 165, protein: 31, fatTotal: 3.6, sodium: 74)

    private func logEntry(_ amount: Double, measure: FoodMeasure) -> LogEntry {
        LogEntry(
            timestamp: .now, mealSlot: .lunch, foodName: measure == .mass ? "Chicken breast" : "Oat drink",
            amount: RawAmount(amount, measure: measure),
            snapshot: SnapshotMath.snapshot(per100g: per100, grams: amount),
            measure: measure
        )
    }

    @Test func gramEntryRoundTripsAndScales() throws {
        let entry = logEntry(150, measure: .mass)
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings == false)
        #expect(basis.amount == 150)
        #expect(basis.choice.isRecipe == false)
        #expect(basis.choice.measure == .mass)
        #expect(basis.choice.name == "Chicken breast")
        #expect(basis.choice.lastAmount == nil)
        #expect(nearly(basis.snapshot(for: 150), entry.snapshot))
        #expect(nearly(basis.snapshot(for: 300), entry.snapshot.map { $0 * 2 }))
        #expect(basis.rawAmount(for: 300) == RawAmount(grams: 300))
        #expect(nearly(basis.choice.snapshot(for: 150), basis.snapshot(for: 150)))
    }

    /// A volume entry has no grams at all; the amount it scales is its millilitres.
    @Test func volumeEntryScalesItsMillilitres() throws {
        let entry = logEntry(250, measure: .volume)
        #expect(entry.grams == 0)
        #expect(entry.millilitres == 250)
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings == false)
        #expect(basis.amount == 250)
        #expect(basis.choice.measure == .volume)
        #expect(nearly(basis.snapshot(for: 250), entry.snapshot))
        #expect(basis.rawAmount(for: 500) == RawAmount(millilitres: 500))
    }

    @Test func recipeEntryRoundTripsInServings() throws {
        let perServing = Nutrition(energy: 318, protein: 17.6, carbohydrates: 49.1, fiber: 9.9)
        let entry = LogEntry(
            timestamp: .now, mealSlot: .dinner, foodName: "Lentil soup", amount: RawAmount(grams: 450),
            snapshot: RecipeMath.snapshot(perServing: perServing, servings: 1.5)
        )
        entry.servings = 1.5
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings)
        #expect(basis.amount == 1.5)
        #expect(basis.choice.isRecipe)
        #expect(basis.choice.amountPerServing == RawAmount(grams: 300))
        #expect(nearly(basis.snapshot(for: 1.5), entry.snapshot))
        #expect(nearly(basis.choice.perUnit, perServing))
        #expect(basis.rawAmount(for: 2) == RawAmount(grams: 600))
        #expect(basis.choice.rawAmount(for: 2) == RawAmount(grams: 600))
    }

    /// A recipe of a solid and a liquid records both, and correcting the servings scales
    /// each part on its own. Nothing is ever converted into the other.
    @Test func mixedRecipeEntryScalesBothParts() throws {
        let perServing = Nutrition(energy: 318, protein: 17.6)
        let entry = LogEntry(
            timestamp: .now, mealSlot: .dinner, foodName: "Lentil soup",
            amount: RawAmount(grams: 350.625, millilitres: 150),
            snapshot: RecipeMath.snapshot(perServing: perServing, servings: 1.5)
        )
        entry.servings = 1.5
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.amount == 1.5)
        #expect(basis.choice.amountPerServing?.grams == 233.75)
        #expect(basis.choice.amountPerServing?.millilitres == 100)
        #expect(basis.rawAmount(for: 1.5) == RawAmount(grams: 350.625, millilitres: 150))
        #expect(basis.rawAmount(for: 2).grams == 467.5)
        #expect(basis.rawAmount(for: 2).millilitres == 200)
    }

    @Test func nothingToScaleWithoutAnAmount() {
        #expect(EntryAmountBasis(entry: logEntry(0, measure: .mass)) == nil)
        #expect(EntryAmountBasis(entry: logEntry(-20, measure: .mass)) == nil)
        #expect(EntryAmountBasis(entry: logEntry(0, measure: .volume)) == nil)

        // Grams recorded but the entry says it was counted in millilitres: there is no
        // amount in the unit its snapshot was frozen against, so there is nothing to scale.
        let mismatched = logEntry(150, measure: .mass)
        mismatched.measure = .volume
        #expect(EntryAmountBasis(entry: mismatched) == nil)

        let noServings = logEntry(150, measure: .mass)
        noServings.servings = 0
        #expect(EntryAmountBasis(entry: noServings) == nil)
        noServings.servings = -1
        #expect(EntryAmountBasis(entry: noServings) == nil)
    }

    /// An estimate has no food and no recipe; it is measured in grams like any other entry.
    @Test func estimateBehavesLikeAGramEntry() throws {
        let portion = Nutrition(energy: 180, protein: 9.4, carbohydrates: 14.2, fatTotal: 9.6)
        let entry = LogEntry(
            timestamp: .now, mealSlot: .snack, foodName: "Latte",
            amount: RawAmount(grams: 250), snapshot: portion
        )
        entry.isEstimate = true
        let basis = try #require(EntryAmountBasis(entry: entry))

        #expect(basis.isServings == false)
        #expect(basis.amount == 250)
        #expect(basis.choice.attribution == nil)
        #expect(basis.choice.source == .custom(foodID: entry.id))
        #expect(nearly(basis.snapshot(for: 250), portion))
        #expect(nearly(basis.snapshot(for: 125), portion.map { $0 / 2 }))
        #expect(basis.rawAmount(for: 125) == RawAmount(grams: 125))
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
