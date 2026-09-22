import Foundation
import Testing
@testable import Omnomnom

/// A bundled database that answers from a fixed table, or fails every search.
nonisolated struct FakeRepository: FoodSearching {
    var hits: [String: [BundledFood]] = [:]
    var failure: FoodRepositoryError?

    func search(_ text: String) async throws -> [BundledFood] {
        if let failure { throw failure }
        return hits[text] ?? []
    }
}

/// The lookup that grounds an estimate: the generic term first, the shown name second,
/// and a row left unmatched rather than filled with anything invented.
struct EstimateResolverTests {
    private func food(_ id: Int, _ name: String) -> BundledFood {
        BundledFood(id: id, name: name, category: nil, per100g: Nutrition(energy: 149, protein: 10), popularity: id)
    }

    private func item(name: String, term: String, grams: Double = 100) -> EstimatedDraftItem {
        EstimatedDraftItem(name: name, lookupTerm: term, grams: grams)
    }

    @Test func theLookupTermIsSearchedBeforeTheShownName() async {
        let repository = FakeRepository(hits: [
            "scrambled eggs": [food(1, "Eggs, scrambled, cooked"), food(2, "Egg substitute")],
            "my scramble": [food(3, "Scramble mix")],
        ])
        let resolved = await EstimateResolver(repository: repository).resolve([item(name: "my scramble", term: "scrambled eggs")])
        #expect(resolved.count == 1)
        #expect(resolved[0].choice?.source == .bundled(id: 1))
        #expect(resolved[0].choice?.name == "Eggs, scrambled, cooked")
        #expect(resolved[0].name == "my scramble")
    }

    @Test func theShownNameIsTheFallbackWhenTheTermFindsNothing() async {
        let repository = FakeRepository(hits: ["dark toast": [food(7, "Bread, rye")]])
        let items = [item(name: "dark toast", term: "pumpernickel loaf"), item(name: "dark toast", term: "")]
        let resolved = await EstimateResolver(repository: repository).resolve(items)
        #expect(resolved.map { $0.choice?.name } == ["Bread, rye", "Bread, rye"])
    }

    @Test func nothingFoundLeavesTheRowWithoutAFood() async {
        let resolved = await EstimateResolver(repository: FakeRepository()).resolve([item(name: "moon cheese", term: "lunar dairy")])
        #expect(resolved[0].choice == nil)
        #expect(resolved[0].nutrition == nil)
    }

    @Test func aFailedSearchLeavesTheRowWithoutAFoodAndDoesNotPropagate() async {
        let repository = FakeRepository(hits: ["butter": [food(9, "Butter, salted")]], failure: .databaseMissing)
        let resolved = await EstimateResolver(repository: repository).resolve([item(name: "Butter", term: "butter")])
        #expect(resolved.count == 1)
        #expect(resolved[0].choice == nil)
    }

    @Test func orderAndWeightsAreKeptAndValuesComeFromTheMatch() async {
        let repository = FakeRepository(hits: [
            "scrambled eggs": [food(1, "Eggs, scrambled, cooked")],
            "butter": [food(9, "Butter, salted")],
        ])
        let items = [
            item(name: "Scrambled eggs", term: "scrambled eggs", grams: 120),
            item(name: "Mystery", term: "nothing here", grams: 50),
            item(name: "Butter", term: "butter", grams: 8),
        ]
        let resolved = await EstimateResolver(repository: repository).resolve(items)
        #expect(resolved.map(\.name) == ["Scrambled eggs", "Mystery", "Butter"])
        #expect(resolved.map(\.id) == items.map(\.id))
        #expect(resolved.map { $0.choice?.name } == ["Eggs, scrambled, cooked", nil, "Butter, salted"])
        #expect(resolved[0].grams == 120)
        // 149 kcal per 100 g of the matched row, never anything the model said.
        #expect(resolved[0].nutrition?.energy == 178.8)
        #expect(resolved[1].nutrition == nil)
    }
}
