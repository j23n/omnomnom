import Testing
@testable import Omnomnom

/// What the model says becomes rows to look up: names cleaned, terms kept, weights
/// bounded, and nothing else carried over.
struct EstimateConversionTests {
    private func item(name: String = "Egg", term: String = "scrambled eggs", grams: Double = 50) -> EstimatedItem {
        EstimatedItem(name: name, lookupTerm: term, grams: grams)
    }

    private func choice(_ name: String, energy: Double, protein: Double) -> FoodChoice {
        FoodChoice(
            source: .bundled(id: name.count), name: name, perUnit: Nutrition(energy: energy, protein: protein)
        )
    }

    @Test func nameWeightAndLookupTermSurviveTheConversion() {
        let result = EstimateConversion.convert(MealEstimate(items: [item()], note: " One large egg. "))
        #expect(result.note == "One large egg.")
        #expect(result.items.count == 1)
        let row = result.items[0]
        #expect(row.name == "Egg")
        #expect(row.lookupTerm == "scrambled eggs")
        #expect(row.grams == 50)
    }

    @Test func itemsWithoutAUsableWeightAreDropped() {
        let estimate = MealEstimate(
            items: [item(grams: 0), item(name: "Ghost", grams: -5), item(grams: .nan), item(name: "Kept")], note: ""
        )
        #expect(EstimateConversion.convert(estimate).items.map(\.name) == ["Kept"])
    }

    @Test func weightsAreCappedToTheAmountFieldsBounds() {
        let estimate = MealEstimate(items: [item(grams: 9000), item(name: "Crumb", grams: 0.01)], note: "")
        let rows = EstimateConversion.convert(estimate).items
        #expect(rows[0].grams == Formatters.maximumAmount)
        #expect(rows[1].grams == Formatters.minimumAmount)
    }

    @Test func namesAreTrimmedCappedAndNeverBlank() {
        let long = String(repeating: "x", count: 150)
        let estimate = MealEstimate(items: [item(name: "  Toast \n"), item(name: long), item(name: "   ")], note: "")
        let names = EstimateConversion.convert(estimate).items.map(\.name)
        #expect(names[0] == "Toast")
        #expect(names[1].count == EstimateConversion.maximumNameLength)
        #expect(names[2] == EstimateConversion.fallbackName)
    }

    @Test func lookupTermsAreTrimmedAndMayStayEmpty() {
        let estimate = MealEstimate(items: [item(term: "  rye bread \n"), item(term: "   ")], note: "")
        let terms = EstimateConversion.convert(estimate).items.map(\.lookupTerm)
        #expect(terms == ["rye bread", ""])
    }

    @Test func totalsSumTheMatchedRowsWithZeroForNothing() {
        let matched = ResolvedEstimateItem(name: "Egg", grams: 100, choice: choice("Egg", energy: 149, protein: 10))
        let other = ResolvedEstimateItem(name: "Toast", grams: 50, choice: choice("Toast", energy: 260, protein: 8))
        let unmatched = ResolvedEstimateItem(name: "Sauce", grams: 30, choice: nil)
        let totals = EstimateConversion.totals(of: [matched, other, unmatched])
        #expect(totals.energy == 279)
        #expect(totals.protein == 14)
        #expect(totals.fiber == 0)
        #expect(EstimateConversion.totals(of: []) == Nutrition.zero)
    }

    @Test func noteIsCapped() {
        let note = String(repeating: "n", count: 500)
        #expect(EstimateConversion.convert(MealEstimate(items: [], note: note)).note.count == EstimateConversion.maximumNoteLength)
    }
}
