import Foundation
import Testing
@testable import Omnomnom

struct RecipeDraftTests {
    private let oats = FoodChoice(source: .bundled(id: 1), name: "Oats", perUnit: Nutrition(energy: 389, fiber: 10.6))
    private let milk = FoodChoice(source: .custom(foodID: UUID()), name: "Milk", perUnit: Nutrition(energy: 61, sugar: 5.05))

    @Test func addingStartsAtTheDefaultGramsAndFreezesTheChoice() {
        var draft = RecipeDraft()
        draft.add(oats)
        #expect(draft.ingredients.count == 1)
        #expect(draft.ingredients[0].grams == RecipeDraft.defaultGrams)
        #expect(draft.ingredients[0].name == "Oats")
        #expect(draft.ingredients[0].source == .bundled(id: 1))
        #expect(draft.ingredients[0].energy == 389)
    }

    @Test func recipesDoNotNest() {
        var draft = RecipeDraft()
        draft.add(FoodChoice(source: .recipe(id: UUID()), name: "Chili", perUnit: Nutrition(energy: 400), gramsPerServing: 250))
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
        draft.ingredients[0].gramsText = "abc"
        #expect(!draft.isValid)
        draft.ingredients[0].gramsText = "40"
        draft.servings = 0
        #expect(!draft.isValid)
        draft.servings = 0.5
        #expect(draft.isValid)
    }

    @Test func totalsSkipRowsStillBeingTyped() {
        var draft = RecipeDraft()
        draft.add(oats)
        draft.add(milk)
        draft.ingredients[0].gramsText = "40"
        draft.ingredients[1].gramsText = "200"
        draft.servings = 2
        #expect(draft.totalWeight == 240)
        #expect(draft.gramsPerServing == 120)
        #expect(draft.perServing.energy.map { abs($0 - 138.8) < 0.0001 } == true)
        draft.ingredients[1].gramsText = ""
        #expect(draft.totalWeight == 40)
        #expect(draft.perServing.sugar == nil)
    }
}
