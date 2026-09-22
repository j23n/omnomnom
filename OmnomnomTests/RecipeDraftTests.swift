import Foundation
import Testing
@testable import Omnomnom

struct RecipeDraftTests {
    private let oats = FoodChoice(source: .bundled(id: 1), name: "Oats", perUnit: Nutrition(energy: 389, fiber: 10.6))
    private let milk = FoodChoice(source: .custom(foodID: UUID()), name: "Milk", perUnit: Nutrition(energy: 61, sugar: 5.05))

    @Test func addingStartsAtTheDefaultAmountAndFreezesTheChoice() {
        var draft = RecipeDraft()
        draft.add(oats)
        #expect(draft.ingredients.count == 1)
        #expect(draft.ingredients[0].amount == RecipeDraft.defaultAmount)
        #expect(draft.ingredients[0].name == "Oats")
        #expect(draft.ingredients[0].source == .bundled(id: 1))
        #expect(draft.ingredients[0].measure == .mass)
        #expect(draft.ingredients[0].energy == 389)
    }

    @Test func recipesDoNotNest() {
        var draft = RecipeDraft()
        draft.add(FoodChoice(
            source: .recipe(id: UUID()), name: "Chili", perUnit: Nutrition(energy: 400),
            amountPerServing: RawAmount(grams: 250)
        ))
        #expect(draft.ingredients.isEmpty)
    }

    @Test func validityNeedsNameServingsAndParsableRows() {
        var draft = RecipeDraft()
        #expect(!draft.isValid)
        draft.name = "  Porridge "
        #expect(!draft.isValid)
        draft.add(oats)
        #expect(draft.isValid)
        #expect(draft.trimmedName == "Porridge")
        draft.ingredients[0].amountText = "abc"
        #expect(!draft.isValid)
        draft.ingredients[0].amountText = "40"
        draft.servings = 0
        #expect(!draft.isValid)
        draft.servings = 0.5
        #expect(draft.isValid)
    }

    @Test func photoIsPartOfTheDraft() {
        var draft = RecipeDraft()
        #expect(draft.photo == nil)
        let plain = draft
        draft.photo = Data([0xFF, 0xD8, 0x01])
        #expect(draft != plain)
        #expect(draft.photo == Data([0xFF, 0xD8, 0x01]))
        draft.photo = nil
        #expect(draft == plain)
    }

    @Test func totalsSkipRowsStillBeingTyped() {
        var draft = RecipeDraft()
        draft.add(oats)
        draft.add(milk)
        draft.ingredients[0].amountText = "40"
        draft.ingredients[1].amountText = "200"
        draft.servings = 2
        #expect(draft.totalAmount == RawAmount(grams: 240))
        #expect(draft.amountPerServing == RawAmount(grams: 120))
        #expect(draft.perServing.energy.map { abs($0 - 138.8) < 0.0001 } == true)
        draft.ingredients[1].amountText = ""
        #expect(draft.totalAmount == RawAmount(grams: 40))
        #expect(draft.perServing.sugar == nil)
    }

    /// Oats by weight and a milk measured in millilitres: the raw total says both, the
    /// per-serving figure divides each part, and the nutrition is unaffected.
    @Test func mixedUnitsAreTotalledApart() {
        let oatMilk = FoodChoice(
            source: .custom(foodID: UUID()), name: "Oat drink",
            perUnit: Nutrition(energy: 46, sugar: 4), measure: .volume
        )
        var draft = RecipeDraft()
        draft.add(oats)
        draft.add(oatMilk)
        draft.ingredients[0].amountText = "40"
        draft.ingredients[1].amountText = "200"
        draft.servings = 2

        #expect(draft.ingredients[1].measure == .volume)
        #expect(draft.totalAmount == RawAmount(grams: 40, millilitres: 200))
        #expect(draft.amountPerServing == RawAmount(grams: 20, millilitres: 100))
        #expect(draft.totalAmount.text == "40 g + 200 ml")
        #expect(draft.perServing.energy.map { abs($0 - 123.8) < 0.0001 } == true)
        #expect(draft.isValid == false)
        draft.name = "Overnight oats"
        #expect(draft.isValid)
    }
}
