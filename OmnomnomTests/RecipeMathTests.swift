import Testing
@testable import Omnomnom

struct RecipeMathTests {
    /// 200 g cooked-rice equivalent and 100 g chicken; fiber unknown on both, sugar only on one.
    private let rice = Nutrition(energy: 130, protein: 2.69, carbohydrates: 28.2, sodium: 1)
    private let chicken = Nutrition(energy: 165, protein: 31, fatTotal: 3.6, sugar: 0)
    private let stock = Nutrition(energy: 4, sodium: 330)

    private var ingredients: [(amount: Double, measure: FoodMeasure, per100: Nutrition)] {
        [(amount: 200, measure: .mass, per100: rice), (amount: 100, measure: .mass, per100: chicken)]
    }

    @Test func totalSumsAmountAndScaledNutrients() {
        let total = RecipeMath.total(ingredients: ingredients)
        #expect(total.amount.grams == 300)
        #expect(total.amount.millilitres == 0)
        #expect(total.nutrition.energy == 425)
        #expect(total.nutrition.protein.map { abs($0 - 36.38) < 0.0001 } == true)
        #expect(total.nutrition.carbohydrates.map { abs($0 - 56.4) < 0.0001 } == true)
    }

    /// The app does not know a density, so a litre of stock is never added to a kilo of
    /// rice. The nutrition still sums, because each row scales against its own amount.
    @Test func mixedUnitsAreCountedApartWhileNutritionStillSums() {
        let mixed: [(amount: Double, measure: FoodMeasure, per100: Nutrition)] =
            ingredients + [(amount: 500, measure: .volume, per100: stock)]
        let total = RecipeMath.total(ingredients: mixed)
        #expect(total.amount.grams == 300)
        #expect(total.amount.millilitres == 500)
        #expect(total.nutrition.energy == 445)
        #expect(total.nutrition.sodium.map { abs($0 - 1652) < 0.0001 } == true)

        let perServing = RecipeMath.amountPerServing(total: total.amount, servings: 4)
        #expect(perServing.grams == 75)
        #expect(perServing.millilitres == 125)
        #expect(perServing.text == "75 g + 125 ml")
    }

    @Test func missingNutrientStaysNilOnlyWhenEveryIngredientLacksIt() {
        let total = RecipeMath.total(ingredients: ingredients).nutrition
        #expect(total.fiber == nil)
        #expect(total.fatSaturated == nil)
        #expect(total.sugar == 0)
        #expect(total.fatTotal.map { abs($0 - 3.6) < 0.0001 } == true)
        #expect(total.sodium == 2)
    }

    @Test func noIngredientsAmountToNothingAndKnowNothing() {
        let total = RecipeMath.total(ingredients: [])
        #expect(total.amount == .zero)
        #expect(total.nutrition == .empty)
    }

    @Test func perServingDividesEveryPresentNutrient() {
        let total = RecipeMath.total(ingredients: ingredients).nutrition
        let perServing = RecipeMath.perServing(total: total, servings: 4)
        #expect(perServing.energy == 106.25)
        #expect(perServing.sodium == 0.5)
        #expect(perServing.fiber == nil)
    }

    @Test func amountPerServingDividesEveryPart() {
        let total = RawAmount(grams: 300, millilitres: 150)
        #expect(RecipeMath.amountPerServing(total: total, servings: 4).grams == 75)
        #expect(RecipeMath.amountPerServing(total: total, servings: 4).millilitres == 37.5)
        #expect(RecipeMath.amountPerServing(total: RawAmount(grams: 300), servings: 1.5).grams == 200)
    }

    @Test func zeroServingsIsTreatedAsOne() {
        let total = Nutrition(energy: 100)
        #expect(RecipeMath.perServing(total: total, servings: 0).energy == 100)
        #expect(RecipeMath.perServing(total: total, servings: -2).energy == 100)
        #expect(RecipeMath.amountPerServing(total: RawAmount(grams: 300), servings: 0).grams == 300)
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
