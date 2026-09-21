import Testing
@testable import Omnomnom

/// The snapshot is a value computed once; editing the recipe afterwards must not reach it.
struct RecipeSnapshotTests {
    private let oats = Nutrition(energy: 389, protein: 16.9, fiber: 10.6)
    private let milk = Nutrition(energy: 61, protein: 3.15, sugar: 5.05)

    private func snapshot(of ingredients: [(grams: Double, per100g: Nutrition)], servings: Double, logged: Double) -> Nutrition {
        let total = RecipeMath.total(ingredients: ingredients).nutrition
        return RecipeMath.snapshot(perServing: RecipeMath.perServing(total: total, servings: servings), servings: logged)
    }

    @Test func editingIngredientsAfterwardsLeavesTheSnapshotAlone() {
        var ingredients = [(grams: 40.0, per100g: oats), (grams: 200.0, per100g: milk)]
        let frozen = snapshot(of: ingredients, servings: 1, logged: 1)
        let copy = frozen

        ingredients[0].grams = 80
        ingredients.append((grams: 30, per100g: Nutrition(energy: 400, sugar: 100)))
        let recomputed = snapshot(of: ingredients, servings: 1, logged: 1)

        #expect(frozen == copy)
        #expect(recomputed != frozen)
        #expect(frozen.energy.map { abs($0 - 277.6) < 0.0001 } == true)
        #expect(recomputed.energy.map { abs($0 - 553.2) < 0.0001 } == true)
    }

    @Test func changingServingsAfterwardsLeavesTheSnapshotAlone() {
        let ingredients = [(grams: 40.0, per100g: oats), (grams: 200.0, per100g: milk)]
        let frozen = snapshot(of: ingredients, servings: 2, logged: 1)
        let after = snapshot(of: ingredients, servings: 4, logged: 1)
        #expect(frozen.energy.map { abs($0 - 138.8) < 0.0001 } == true)
        #expect(after.energy.map { abs($0 - 69.4) < 0.0001 } == true)
        #expect(frozen != after)
    }

    @Test func snapshotIsPerServingTimesServingsLogged() {
        let ingredients = [(grams: 40.0, per100g: oats), (grams: 200.0, per100g: milk)]
        let perServing = RecipeMath.perServing(total: RecipeMath.total(ingredients: ingredients).nutrition, servings: 2)
        let logged = RecipeMath.snapshot(perServing: perServing, servings: 0.5)
        #expect(logged.energy.map { abs($0 - 69.4) < 0.0001 } == true)
        #expect(logged.fiber.map { abs($0 - 1.06) < 0.0001 } == true)
        #expect(logged.fatTotal == nil)
    }
}
