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
        #expect(choice.amountPerServing == nil)
        #expect(choice.measure == .mass)
        #expect(choice.unitText == "100 g")
    }

    /// A food measured in millilitres carries that through every label the row and the
    /// Quantity sheet read off the choice; the arithmetic is the same either way.
    @Test func volumeFoodNamesMillilitresEverywhere() {
        let oatDrink = Nutrition(energy: 46, protein: 1, carbohydrates: 6.6)
        let choice = FoodChoice(
            source: .product(foodID: UUID()), name: "Oat drink", perUnit: oatDrink, measure: .volume, lastAmount: 250
        )
        #expect(choice.measure == .volume)
        #expect(choice.unitText == "100 ml")
        #expect(choice.amountText(250) == "250 ml")
        #expect(choice.rawAmount(for: 250) == RawAmount(millilitres: 250))
        #expect(choice.snapshot(for: 200).energy == 92)
        #expect(choice.with(lastAmount: 300).measure == .volume)
    }

    @Test func foodAmountIsGramsAndSnapshotScalesPer100g() {
        let choice = FoodChoice(source: .custom(foodID: UUID()), name: "Granola", perUnit: apple)
        #expect(choice.rawAmount(for: 150) == RawAmount(grams: 150))
        #expect(choice.snapshot(for: 200).energy == 104)
        #expect(choice.snapshot(for: 200).sodium == nil)
        #expect(choice.bundledID == nil)
        #expect(choice.amountText(62) == "62 g")
    }

    @Test func recipeAmountIsServingsAndSnapshotMultipliesPerServing() {
        let perServing = Nutrition(energy: 400, protein: 20)
        let choice = FoodChoice(
            source: .recipe(id: UUID()), name: "Chili", perUnit: perServing,
            amountPerServing: RawAmount(grams: 200, millilitres: 50), lastAmount: 2
        )
        #expect(choice.isRecipe)
        #expect(choice.bundledID == nil)
        #expect(choice.rawAmount(for: 1.5) == RawAmount(grams: 300, millilitres: 75))
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

    @Test func photoRidesAlongThroughPrefill() {
        let photo = Data([0xFF, 0xD8, 0x03])
        let choice = FoodChoice(source: .custom(foodID: UUID()), name: "Granola", perUnit: apple, photo: photo)
        #expect(choice.photo == photo)
        #expect(choice.with(lastAmount: 40).photo == photo)
        #expect(FoodChoice(source: .bundled(id: 1), name: "Apple", perUnit: apple).photo == nil)
        #expect(choice != FoodChoice(source: choice.source, name: "Granola", perUnit: apple))
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
