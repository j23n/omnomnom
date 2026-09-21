import Foundation
import Testing
@testable import Omnomnom

struct FoodChoiceTests {
    private let apple = Nutrition(energy: 52, protein: 0.26, carbohydrates: 13.8, fiber: 2.4)

    @Test func bundledHitMapsToItsSource() {
        let bundled = BundledFood(id: 42, name: "Apple", category: "Fruit", per100g: apple, popularity: 3)
        let choice = FoodChoice(bundled: bundled)
        #expect(choice.source == .bundled(id: 42))
        #expect(choice.id == .bundled(id: 42))
        #expect(choice.bundledID == 42)
        #expect(choice.isRecipe == false)
        #expect(choice.lastAmount == nil)
        #expect(choice.gramsPerServing == nil)
        #expect(choice.unitText == "100 g")
    }

    @Test func foodAmountIsGramsAndSnapshotScalesPer100g() {
        let choice = FoodChoice(source: .custom(foodID: UUID()), name: "Granola", perUnit: apple)
        #expect(choice.grams(for: 150) == 150)
        #expect(choice.snapshot(for: 200).energy == 104)
        #expect(choice.snapshot(for: 200).sodium == nil)
        #expect(choice.bundledID == nil)
        #expect(choice.amountText(62) == "62 g")
    }

    @Test func recipeAmountIsServingsAndSnapshotMultipliesPerServing() {
        let perServing = Nutrition(energy: 400, protein: 20)
        let choice = FoodChoice(source: .recipe(id: UUID()), name: "Chili", perUnit: perServing, gramsPerServing: 250, lastAmount: 2)
        #expect(choice.isRecipe)
        #expect(choice.bundledID == nil)
        #expect(choice.grams(for: 1.5) == 375)
        #expect(choice.snapshot(for: 1.5).energy == 600)
        #expect(choice.snapshot(for: 1.5).protein == 30)
        #expect(choice.snapshot(for: 1.5).fiber == nil)
        #expect(choice.unitText == "serving")
        #expect(choice.amountText(1) == "1 serving")
        #expect(choice.amountText(2) == "2 servings")
    }

    @Test func withLastAmountKeepsIdentity() {
        let choice = FoodChoice(source: .bundled(id: 7), name: "Rice", perUnit: apple)
        let prefilled = choice.with(lastAmount: 158)
        #expect(prefilled.id == choice.id)
        #expect(prefilled.lastAmount == 158)
        #expect(prefilled.name == choice.name)
        #expect(prefilled.perUnit == choice.perUnit)
    }

    @Test func sourcesAreDistinctAcrossKinds() {
        let id = UUID()
        let sources: Set<FoodChoice.Source> = [
            .bundled(id: 1), .bundled(id: 2), .custom(foodID: id), .product(foodID: id), .recipe(id: id),
        ]
        #expect(sources.count == 5)
        #expect(FoodChoice.Source.custom(foodID: id) != .recipe(id: id))
        #expect(FoodChoice.Source.custom(foodID: id) != .product(foodID: id))
    }

    @Test func productKeepsItsAttributionThroughPrefill() {
        let attribution = ProductAttribution(barcode: "4006381333931", brand: "Ferrero", source: .openFoodFacts)
        let choice = FoodChoice(source: .product(foodID: UUID()), name: "Nutella", perUnit: apple, attribution: attribution)
        #expect(choice.attribution?.isFromOpenFoodFacts == true)
        #expect(choice.isRecipe == false)
        #expect(choice.bundledID == nil)
        let prefilled = choice.with(lastAmount: 15)
        #expect(prefilled.attribution == attribution)
        #expect(prefilled.lastAmount == 15)
        let typed = ProductAttribution(barcode: "96385074", brand: nil, source: .manual)
        #expect(!typed.isFromOpenFoodFacts)
    }
}
