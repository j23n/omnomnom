import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// A driving model that answers from a script, or fails.
///
/// `asked` doubles as a way to prove it was never reached: a test that expects recall to
/// answer gives the driver a failure and then checks it was not called at all.
@MainActor
final class FakeDriver: LineDriving {
    var answer = ResolvedLine(items: [])
    var pool = LineCandidatePool()
    var failure: EstimationError?
    private(set) var asked = 0

    func resolve(_ input: EstimationInput) async throws -> DrivenLine {
        asked += 1
        if let failure { throw failure }
        return DrivenLine(answer: answer, pool: pool)
    }
}

/// The one-call path: what a model that searched for itself turns into on the sheet.
@MainActor
struct LineResolverToolsTests {
    private func storedFood(_ name: String, in context: ModelContext) -> Food {
        let food = Food(name: name, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 200))
        context.insert(food)
        return food
    }

    private func match(_ id: Int, _ name: String, kcal: Double = 370, ingredient: Bool = false) -> FoodMatch {
        FoodMatch(
            food: BundledFood(
                id: id, name: name, category: "cereals", per100g: Nutrition(energy: kcal, protein: 13),
                popularity: 0, isIngredient: ingredient
            ),
            score: 0.8
        )
    }

    private func item(
        candidate: Int, name: String = "oats", grams: Double = 45,
        certainty: VerdictCertainty = .certain, implausible: Bool = false
    ) -> ResolvedLineItem {
        ResolvedLineItem(
            name: name, candidate: candidate, grams: grams, certainty: certainty,
            implausible: implausible
        )
    }

    /// A driver holding one bundled candidate, numbered 1, and whatever items a test wants.
    private func driver(
        items: [ResolvedLineItem], offering foods: [FoodMatch], meal: EstimatedMeal = .breakfast
    ) -> FakeDriver {
        let fake = FakeDriver()
        var pool = LineCandidatePool()
        _ = pool.add(foods: foods)
        fake.pool = pool
        fake.answer = ResolvedLine(items: items, meal: meal, note: "a usual bowl")
        return fake
    }

    private func resolver(_ context: ModelContext, _ fake: FakeDriver) -> LineResolver {
        LineResolver(context: context, repository: FakeRepository(), driver: fake)
    }

    @Test func aChosenRowCarriesItsOwnValuesAndTheModelsWeight() async throws {
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 1)], offering: [match(1, "Oat flakes")])
        let resolution = await resolver(context, fake).resolve("a bowl of oats")

        let row = try #require(resolution.rows.first)
        #expect(row.choice?.name == "Oat flakes")
        #expect(row.origin == .database)
        #expect(row.confidence == .settled)
        #expect(row.amount == 45)
        // Every figure is the row's own, scaled. Nothing on screen is a number the model
        // produced except the weight. Compared with a tolerance because 45/100 is not
        // exact in binary and the assertion is about the scaling, not the last bit.
        let energy = try #require(row.nutrition?.energy)
        #expect(abs(energy - 166.5) < 0.001)
        #expect(resolution.meal == .breakfast)
        #expect(resolution.canLog)
    }

    @Test func theLineCountsAsCheckedBecauseTheModelReadTheRows() async throws {
        // More thoroughly than the other path means by it: these are rows the model chose
        // from a list it asked for, rather than rows a retriever chose and it confirmed.
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 1)], offering: [match(1, "Oat flakes")])
        #expect(await resolver(context, fake).resolve("oats").wasChecked)
    }

    @Test func aCandidateNobodyOfferedReadsAsNoneOfThese() async throws {
        // The whole invariant on this path. The model picks what to search for, so the
        // shortlist is not fixed in advance — but what came back is, and an id outside it
        // cannot name a food.
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 4_242)], offering: [match(1, "Oat flakes")])
        let resolution = await resolver(context, fake).resolve("oats")

        let row = try #require(resolution.rows.first)
        #expect(row.choice == nil)
        #expect(row.confidence == .unsure)
        #expect(row.blocks)
        #expect(!resolution.canLog)
        // The row still names what the line called it, so the user knows what to settle.
        #expect(row.displayName == "oats")
    }

    @Test func zeroIsAnAnswerAndLeavesTheFoodForTheUser() async throws {
        // Correct for a food neither search holds, and better than a row that is nearly
        // right: the user picks or removes it.
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 0, name: "my gran's stollen")], offering: [])
        let resolution = await resolver(context, fake).resolve("my gran's stollen")

        let row = try #require(resolution.rows.first)
        #expect(row.choice == nil)
        #expect(row.blocks)
        #expect(row.displayName == "my gran's stollen")
    }

    @Test func anIngredientFormNeverSettlesEvenWhenTheModelIsCertain() async throws {
        // The one place this path overrides the model. It is told which candidates are an
        // ingredient or dry form and told they are rarely what was eaten, so choosing one
        // is deliberate and worth more than a score — but coffee powder settled at a
        // portion weight is a hundredfold energy error landing silently in a trend, and
        // one glance is cheap against that.
        let context = try TestStore.context()
        let fake = driver(
            items: [item(candidate: 1, name: "coffee", grams: 400)],
            offering: [match(1, "Coffee, instant, powder", kcal: 350, ingredient: true)]
        )
        let resolution = await resolver(context, fake).resolve("a coffee")

        let row = try #require(resolution.rows.first)
        #expect(row.confidence == .probable)
        #expect(!row.blocks)
        #expect(resolution.glanceCount == 1)
        // And the deterministic guard fires on its own: 400 g of a 350 kcal powder is
        // 1,400 kcal, past the bar, and the model's own flag was left false.
        #expect(row.implausible)
    }

    @Test func certaintyMapsStraightThroughOtherwise() {
        #expect(LineResolver.confidence(.certain, isIngredient: false) == .settled)
        #expect(LineResolver.confidence(.probable, isIngredient: false) == .probable)
        #expect(LineResolver.confidence(.unsure, isIngredient: false) == .unsure)
        // Capped rather than refused, which is where this differs from `FoodMatch`: the
        // scorer has no idea what the row is and this model does.
        #expect(LineResolver.confidence(.certain, isIngredient: true) == .probable)
        #expect(LineResolver.confidence(.unsure, isIngredient: true) == .unsure)
    }

    @Test func anItemWithNoWeightIsDroppedRatherThanGivenOne() async throws {
        // The rule the other path already applies: a dropped row is honest and an invented
        // weight is not.
        let context = try TestStore.context()
        let fake = driver(
            items: [item(candidate: 1, grams: 0), item(candidate: 1, name: "banana", grams: 120)],
            offering: [match(1, "Oat flakes")]
        )
        let resolution = await resolver(context, fake).resolve("oats and a banana")

        #expect(resolution.rows.count == 1)
        #expect(resolution.rows.first?.amount == 120)
    }

    @Test func aWeightBeyondTheFieldsBoundsIsClampedToIt() async throws {
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 1, grams: 99_999)], offering: [match(1, "Oat flakes")])
        let resolution = await resolver(context, fake).resolve("oats")
        #expect(resolution.rows.first?.amount == Formatters.maximumAmount)
    }

    @Test func aDriverThatFailsLeavesNothingRatherThanThrowing() async throws {
        let context = try TestStore.context()
        let fake = driver(items: [item(candidate: 1)], offering: [match(1, "Oat flakes")])
        fake.failure = .failed("the API was unreachable")
        let resolution = await resolver(context, fake).resolve("oats")

        #expect(resolution.isEmpty)
        #expect(!resolution.wasChecked)
        // And it says which failure. An empty sheet and a refused key are the same
        // picture, and only one of them is about what the user typed — "nothing in that
        // looked like a food" sends someone back to rewrite a line that was fine.
        #expect(resolution.failure == "Estimation failed: the API was unreachable")
    }

    @Test func aRefusedKeyReadsAsSomethingToGoAndFix() async throws {
        let context = try TestStore.context()
        let fake = driver(items: [], offering: [])
        fake.failure = .unavailable("The API refused the key. Check it in Settings.")
        let resolution = await resolver(context, fake).resolve("spaghetti")
        #expect(resolution.failure == "The API refused the key. Check it in Settings.")
    }

    @Test func beingCancelledSaysNothingBecauseThereIsNothingToDo() async throws {
        // The user typed on. The answer is about a line they have moved past, and a
        // banner about it would be noise over the line they are writing now.
        let context = try TestStore.context()
        let fake = driver(items: [], offering: [])
        fake.failure = .cancelled
        #expect(await resolver(context, fake).resolve("oats").failure == nil)
    }

    @Test func aLineLoggedBeforeNeverReachesTheModel() async throws {
        // What keeps a repeat under five seconds, and it is the one rung this path keeps.
        let context = try TestStore.context()
        let food = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: food)], in: context
        )
        let fake = driver(items: [item(candidate: 1)], offering: [match(1, "Oat flakes")])
        fake.failure = .failed("the model was asked")
        let resolution = await resolver(context, fake).resolve("oats")

        #expect(fake.asked == 0)
        #expect(resolution.rows.first?.origin == .phrase)
        #expect(resolution.rows.first?.amount == 40)
        #expect(resolution.canLog)
    }

    @Test func aPhotoStillGoesToTheModelEvenWhereALineWouldNot() async throws {
        // Recall is keyed on the line, and a picture is not a line. Two different meals
        // photographed with the same words are not the same meal.
        let context = try TestStore.context()
        let food = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: food)], in: context
        )
        let fake = driver(items: [item(candidate: 1)], offering: [match(1, "Oat flakes")])
        let resolution = await resolver(context, fake)
            .resolve(.photo(Data("not really a photo".utf8), description: "oats"), line: "oats")

        #expect(fake.asked == 1)
        #expect(resolution.rows.first?.origin == .database)
    }

    @Test func withADriverTheComposerKnowsALineCanBeRead() async throws {
        // The composer used to ask whether there was an estimator, which is the wrong
        // question now: a user with Claude configured has no estimator and a model.
        let context = try TestStore.context()
        let fake = driver(items: [], offering: [])
        #expect(resolver(context, fake).canReadALine)
        #expect(!LineResolver(context: context, repository: FakeRepository()).canReadALine)
    }
}
