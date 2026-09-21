import Testing
@testable import Omnomnom

struct RecipeMathTests {
    /// 200 g cooked-rice equivalent and 100 g chicken; fiber unknown on both, sugar only on one.
    private let rice = Nutrition(energy: 130, protein: 2.69, carbohydrates: 28.2, sodium: 1)
    private let chicken = Nutrition(energy: 165, protein: 31, fatTotal: 3.6, sugar: 0)

    private var ingredients: [(grams: Double, per100g: Nutrition)] {
        [(grams: 200, per100g: rice), (grams: 100, per100g: chicken)]
    }

    @Test func totalSumsWeightAndScaledNutrients() {
        let total = RecipeMath.total(ingredients: ingredients)
        #expect(total.weight == 300)
        #expect(total.nutrition.energy == 425)
        #expect(total.nutrition.protein.map { abs($0 - 36.38) < 0.0001 } == true)
        #expect(total.nutrition.carbohydrates.map { abs($0 - 56.4) < 0.0001 } == true)
    }

    @Test func missingNutrientStaysNilOnlyWhenEveryIngredientLacksIt() {
        let total = RecipeMath.total(ingredients: ingredients).nutrition
        #expect(total.fiber == nil)
        #expect(total.fatSaturated == nil)
        #expect(total.sugar == 0)
        #expect(total.fatTotal.map { abs($0 - 3.6) < 0.0001 } == true)
        #expect(total.sodium == 2)
    }

    @Test func noIngredientsWeighNothingAndKnowNothing() {
        let total = RecipeMath.total(ingredients: [])
        #expect(total.weight == 0)
        #expect(total.nutrition == .empty)
    }

    @Test func perServingDividesEveryPresentNutrient() {
        let total = RecipeMath.total(ingredients: ingredients).nutrition
        let perServing = RecipeMath.perServing(total: total, servings: 4)
        #expect(perServing.energy == 106.25)
        #expect(perServing.sodium == 0.5)
        #expect(perServing.fiber == nil)
    }

    @Test func gramsPerServingIsWeightOverServings() {
        #expect(RecipeMath.gramsPerServing(weight: 300, servings: 4) == 75)
        #expect(RecipeMath.gramsPerServing(weight: 300, servings: 1.5) == 200)
    }

    @Test func zeroServingsIsTreatedAsOne() {
        let total = Nutrition(energy: 100)
        #expect(RecipeMath.perServing(total: total, servings: 0).energy == 100)
        #expect(RecipeMath.perServing(total: total, servings: -2).energy == 100)
        #expect(RecipeMath.gramsPerServing(weight: 300, servings: 0) == 300)
    }

    @Test func fractionalServingsSnapshot() {
        let perServing = Nutrition(energy: 106.25, protein: 9.095, sodium: 0.5)
        let snapshot = RecipeMath.snapshot(perServing: perServing, servings: 1.5)
        #expect(snapshot.energy == 159.375)
        #expect(snapshot.protein.map { abs($0 - 13.6425) < 0.0001 } == true)
        #expect(snapshot.sodium == 0.75)
        #expect(snapshot.fiber == nil)
    }
}
