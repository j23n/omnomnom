import Foundation
import Testing
@testable import Omnomnom

/// The on-device driver, in the two parts of it that can be exercised without a device.
///
/// What cannot: `resolve` itself. It builds a real `LanguageModelSession`, and there is no
/// seam to put a fake behind — the session type is concrete and the framework owns the loop
/// it runs, which is the whole reason this driver has no loop of its own. So the request,
/// the searching and the answer cannot be scripted here the way the two HTTP drivers' can,
/// and nothing in this file pretends otherwise.
///
/// What can, and is what would actually break: `LineSearchRun`, which is the shared state
/// the tools write into and the resolver reads out of, and therefore where the
/// can't-invent-a-food invariant lives on this path; and the mapping from the generated
/// shape to the app's own, which is pure. Whether a 3-billion-parameter model chooses *well*
/// is not a test, it is a measurement on a device.
@MainActor
struct FoundationLineResolverTests {
    private func match(_ id: Int, _ name: String, kcal: Double = 370, ingredient: Bool = false) -> FoodMatch {
        FoodMatch(
            food: BundledFood(
                id: id, name: name, category: "cereals", per100g: Nutrition(energy: kcal),
                popularity: 0, isIngredient: ingredient
            ),
            score: 0.8
        )
    }

    private func product(_ code: String, _ name: String, brand: String? = nil) -> ProductRecord {
        ProductRecord(
            code: code, name: name, brand: brand,
            per100g: Nutrition(energy: 400, protein: 8, carbohydrates: 60, fatTotal: 12)
        )
    }

    // MARK: - The searches a tool runs

    @Test func aSearchNumbersItsRowsAndKeepsThem() async throws {
        let search = FakeLineSearch()
        search.foodHits = ["oats": [match(11, "Oat flakes"), match(12, "Oats, rolled")]]
        let run = LineSearchRun(searcher: search)

        let text = await run.foods(matching: "oats")

        #expect(text.contains("id 1: Oat flakes"))
        #expect(text.contains("id 2: Oats, rolled"))
        // The id the model is shown is this request's, not the table's: a bundled row and a
        // product share no namespace, so one counter spans both.
        #expect(run.pool.count == 2)
        #expect(run.pool.candidate(id: 1)?.name == "Oat flakes")
        #expect(run.pool.candidate(id: 11) == nil)
    }

    @Test func idsAreOneSequenceAcrossBothSearches() async throws {
        let search = FakeLineSearch()
        search.foodHits = ["bread": [match(5, "Rye bread")]]
        search.productHits = ["nutella": [product("3017620422003", "Nutella", brand: "Ferrero")]]
        let run = LineSearchRun(searcher: search)

        _ = await run.foods(matching: "bread")
        let second = await run.products(matching: "nutella")

        #expect(second.contains("id 2: Nutella"))
        #expect(run.pool.candidate(id: 1)?.isProduct == false)
        #expect(run.pool.candidate(id: 2)?.isProduct == true)
    }

    @Test func aSearchThatFoundNothingSaysSoRatherThanAnsweringBlank() async throws {
        let run = LineSearchRun(searcher: FakeLineSearch())

        let text = await run.foods(matching: "xyzzy")

        #expect(!text.isEmpty)
        #expect(text == LinePrompt.results([]))
        #expect(run.pool.count == 0)
    }

    @Test func withTheOptInOffTheProductSearchIsRefusedEvenIfItIsCalled() async throws {
        // The tool is not declared when the opt-in is off, so the model cannot ask for it.
        // This is the second guard behind that one: what makes "nothing is asked of Open
        // Food Facts" true even if a later caller forgets to check.
        let search = FakeLineSearch()
        search.searchesProducts = false
        search.productHits = ["nutella": [product("3017620422003", "Nutella")]]
        let run = LineSearchRun(searcher: search)

        let text = await run.products(matching: "nutella")

        #expect(text == LinePrompt.noSuchSearch)
        #expect(run.pool.count == 0)
        #expect(search.productTerms.isEmpty)
    }

    @Test func bothToolsAreNamedAndDescribedFromTheOnePlaceThatOwnsThat() {
        let run = LineSearchRun(searcher: FakeLineSearch())

        // The point of this one: the model is offered the same two searches, under the same
        // names and the same words, as it is over either HTTP protocol. A name that drifted
        // from the description beside it is the failure no test of one file alone catches.
        #expect(FoodSearchTool(run: run).name == LinePrompt.foodTool)
        #expect(FoodSearchTool(run: run).description == LinePrompt.foodToolDescription)
        #expect(ProductSearchTool(run: run).name == LinePrompt.productTool)
        #expect(ProductSearchTool(run: run).description == LinePrompt.productToolDescription)
    }

    // MARK: - The generated shape as the app's own

    @Test func whatWasGeneratedBecomesTheAnswerEveryDriverHandsBack() throws {
        let generated = GeneratedLine(
            items: [
                GeneratedLineItem(name: "oats", candidate: 1, grams: 45, certainty: .certain),
                GeneratedLineItem(
                    name: "butter", candidate: 2, grams: 2_000, certainty: .probable, implausible: true
                ),
            ],
            meal: .breakfast,
            note: "a usual bowl"
        )

        let answer = generated.resolved

        #expect(answer.items.count == 2)
        #expect(answer.meal == .breakfast)
        #expect(answer.note == "a usual bowl")
        let first = try #require(answer.items.first)
        #expect(first.name == "oats")
        #expect(first.candidate == 1)
        #expect(first.grams == 45)
        #expect(first.certainty == .certain)
        #expect(!first.implausible)
        #expect(answer.items[1].implausible)
    }

    @Test func certaintyMeansTheSameHereAsOnEveryOtherPath() {
        // Mapped through `VerdictCertainty` rather than to a confidence directly, so what
        // "probable" is worth on a row goes on being decided in one place for all three.
        #expect(GeneratedCertainty.certain.certainty == .certain)
        #expect(GeneratedCertainty.probable.certainty == .probable)
        #expect(GeneratedCertainty.unsure.certainty == .unsure)
        #expect(GeneratedCertainty.certain.certainty.confidence == .settled)
        #expect(GeneratedCertainty.unsure.certainty.confidence == .unsure)
    }

    @Test func zeroSurvivesTheMappingBecauseItIsAnAnswer() {
        // "Neither search holds this food" has to arrive at `LineResolver` as 0, which is
        // what leaves the row for the user instead of attaching a nearly-right food.
        let answer = GeneratedLine(
            items: [GeneratedLineItem(name: "oat biscuits", candidate: 0, grams: 30, certainty: .unsure)]
        ).resolved

        #expect(answer.items.first?.candidate == 0)
        #expect(answer.meal == .snack)
    }
}
