import Testing
@testable import Omnomnom

/// The model's structure becomes draft rows only through the clamps.
struct EstimateConversionTests {
    private func item(
        name: String = "Egg", grams: Double = 50, kcal: Double = 72, protein: Double = 6.3, carbs: Double = 0.4,
        fat: Double = 4.8, saturated: Double = 1.6, fiber: Double = 0, sugar: Double = 0.2, sodium: Double = 71
    ) -> EstimatedItem {
        EstimatedItem(
            name: name, grams: grams, kcal: kcal, proteinGrams: protein, carbGrams: carbs, fatGrams: fat,
            saturatedFatGrams: saturated, fiberGrams: fiber, sugarGrams: sugar, sodiumMilligrams: sodium
        )
    }

    @Test func valuesBecomeTheSnapshotAsTheyAre() {
        let result = EstimateConversion.convert(MealEstimate(items: [item()], note: " One large egg. "))
        #expect(result.note == "One large egg.")
        #expect(result.warnings.isEmpty)
        #expect(result.items.count == 1)
        let row = result.items[0]
        #expect(row.name == "Egg")
        #expect(row.grams == 50)
        #expect(row.nutrition == Nutrition(energy: 72, protein: 6.3, carbohydrates: 0.4, fatTotal: 4.8, fatSaturated: 1.6, fiber: 0, sugar: 0.2, sodium: 71))
    }

    @Test func itemsWithoutWeightOrWithNegativeEnergyAreDropped() {
        let estimate = MealEstimate(items: [item(grams: 0), item(name: "Ghost", kcal: -5), item(grams: .nan), item(name: "Kept")], note: "")
        let result = EstimateConversion.convert(estimate)
        #expect(result.items.map(\.name) == ["Kept"])
    }

    @Test func valuesAreCappedAndNegativesBecomeZero() {
        let wild = item(grams: 9000, kcal: 1_000_000, protein: -3, sodium: .infinity)
        let row = EstimateConversion.convert(MealEstimate(items: [wild], note: "")).items[0]
        #expect(row.grams == Formatters.maximumGrams)
        #expect(row.nutrition.energy == Formatters.maximumNutrientValue)
        #expect(row.nutrition.protein == 0)
        #expect(row.nutrition.sodium == 0)
    }

    @Test func zeroEnergyWithMacrosIsRecomputedAndNoted() {
        let estimate = MealEstimate(items: [item(name: "Rice", kcal: 0, protein: 4, carbs: 45, fat: 1)], note: "")
        let result = EstimateConversion.convert(estimate)
        #expect(result.items[0].nutrition.energy == 4 * 4 + 4 * 45 + 9 * 1)
        #expect(result.warnings == ["Energy for Rice was computed from its macros."])
    }

    @Test func zeroEnergyWithoutMacrosStaysZero() {
        let estimate = MealEstimate(items: [item(name: "Water", kcal: 0, protein: 0, carbs: 0, fat: 0)], note: "")
        let result = EstimateConversion.convert(estimate)
        #expect(result.items[0].nutrition.energy == 0)
        #expect(result.warnings.isEmpty)
    }

    @Test func namesAreTrimmedCappedAndNeverBlank() {
        let long = String(repeating: "x", count: 150)
        let estimate = MealEstimate(items: [item(name: "  Toast \n"), item(name: long), item(name: "   ")], note: "")
        let names = EstimateConversion.convert(estimate).items.map(\.name)
        #expect(names[0] == "Toast")
        #expect(names[1].count == EstimateConversion.maximumNameLength)
        #expect(names[2] == EstimateConversion.fallbackName)
    }

    @Test func totalsSumTheRowsWithZeroForNothing() {
        let rows = EstimateConversion.convert(MealEstimate(items: [item(protein: 6.5), item(kcal: 28, protein: 1.5)], note: "")).items
        let totals = EstimateConversion.totals(of: rows)
        #expect(totals.energy == 100)
        #expect(totals.protein == 8)
        #expect(EstimateConversion.totals(of: []) == Nutrition.zero)
    }

    @Test func noteIsCapped() {
        let note = String(repeating: "n", count: 500)
        #expect(EstimateConversion.convert(MealEstimate(items: [], note: note)).note.count == EstimateConversion.maximumNoteLength)
    }
}
