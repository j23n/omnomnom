import Foundation
import Testing
@testable import Omnomnom

/// The pool, and the one invariant it carries.
struct LineCandidatePoolTests {
    private func match(_ id: Int, _ name: String, ingredient: Bool = false) -> FoodMatch {
        FoodMatch(
            food: BundledFood(
                id: id, name: name, category: "cereals",
                per100g: Nutrition(energy: 370, protein: 13), popularity: 0, isIngredient: ingredient
            ),
            score: 0.8
        )
    }

    @Test func anIDThisRequestNeverIssuedIsNotAFood() {
        // The whole of the can't-invent-a-food invariant on this path. The validation
        // prompt gets it by handing over a fixed shortlist; here the model chooses what to
        // search for, so what came back is the list.
        var pool = LineCandidatePool()
        _ = pool.add(foods: [match(1, "Oat flakes")])
        #expect(pool.candidate(id: 1) != nil)
        #expect(pool.candidate(id: 0) == nil)
        #expect(pool.candidate(id: 42) == nil)
        // A real table row id is not a candidate id either, which is the point of the
        // separate namespace: nothing can be named by guessing a database key.
        #expect(pool.candidate(id: 370) == nil)
    }

    @Test func aProductWithNoNameIsNotOfferedAtAll() {
        // The index holds a great many records that are a code and nothing else, and the
        // model would be choosing between blanks.
        var pool = LineCandidatePool()
        let offered = pool.add(products: [
            ProductRecord(code: "1", name: nil, brand: "Oatly", per100g: Nutrition(energy: 40)),
            ProductRecord(code: "2", name: "", brand: nil, per100g: Nutrition(energy: 40)),
            ProductRecord(code: "3", name: "Oatly Oat Drink", brand: "Oatly", per100g: Nutrition(energy: 40)),
        ])
        #expect(offered.count == 1)
        #expect(pool.count == 1)
        #expect(offered.first?.name == "Oatly Oat Drink")
    }

    @Test func aPromptLineSaysWhatTellsTwoRowsApart() throws {
        var pool = LineCandidatePool()
        let rows = pool.add(foods: [match(1, "Coffee, instant, powder", ingredient: true)])
        let text = try #require(rows.first?.promptLine)
        #expect(text.hasPrefix("id 1: Coffee, instant, powder"))
        // Energy, because it is what tells a drink from its powder; the marker, because a
        // name cannot carry it; and the gaps, because a row short of a figure sums to a
        // floor rather than a total.
        #expect(text.contains("370 kcal/100 g"))
        #expect(text.contains("ingredient or dry form"))
        #expect(text.contains("figures missing"))
        // A count and never a grade: no percentage and no verdict.
        #expect(!text.contains("%"))
        #expect(!text.lowercased().contains("poor"))
    }

    @Test func aProductSaysWhereItCameFrom() {
        var pool = LineCandidatePool()
        let rows = pool.add(products: [
            ProductRecord(
                code: "1", name: "Oatly Oat Drink", brand: "Oatly",
                per100g: Nutrition(energy: 40, protein: 1, carbohydrates: 6.6, fatTotal: 1.5)
            )
        ])
        let text = rows.first?.promptLine ?? ""
        #expect(text.contains("Oatly"))
        #expect(text.contains("Open Food Facts"))
    }
}
