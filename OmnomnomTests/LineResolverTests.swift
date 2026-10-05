import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// A validator that answers from a fixed script, or fails.
nonisolated struct FakeValidator: MatchValidating {
    var verdicts: [MatchVerdict] = []
    var failure: EstimationError?
    /// Answers fewer verdicts than it was asked for, to exercise the all-or-nothing rule.
    var answerShort = false

    func validate(line: String, items: [ValidationItem]) async throws -> MatchVerdicts {
        if let failure { throw failure }
        if answerShort { return MatchVerdicts(verdicts: verdicts.dropLast().map { $0 }) }
        return MatchVerdicts(verdicts: verdicts)
    }
}

/// An estimator that names foods from a script, or fails.
///
/// Where a test is about what happens *after* a food is named, the fake splits its line on
/// commas and " and " and gives each part 100 g. That is not what a real model does — it is
/// the least interesting thing a model could do, which is the point: these tests are about
/// the rungs below it. A test about the model's own answer supplies `items` itself.
///
/// `failure` doubles as a way to prove a model was never asked: a test that expects recall
/// to answer gives the estimator a failure it should never reach.
nonisolated struct FakeEstimator: MealEstimating {
    var items: [EstimatedItem]?
    var meal: EstimatedMeal = .snack
    var failure: EstimationError?

    func estimate(_ input: EstimationInput) async throws -> MealEstimate {
        if let failure { throw failure }
        if let items { return MealEstimate(items: items, meal: meal, note: "") }
        guard case .text(let line) = input else {
            return MealEstimate(items: [], meal: meal, note: "")
        }
        let named = line
            .replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { EstimatedItem(name: $0, lookupTerm: $0, grams: 100) }
        return MealEstimate(items: named, meal: meal, note: "")
    }
}

/// The four rungs, in order, and what happens when the model is absent or wrong.
struct LineResolverTests {
    private func makeContext() throws -> ModelContext {
        let schema = StoreSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func bundled(
        _ id: Int, _ name: String, ingredient: Bool = false, popularity: Int = 0
    ) -> BundledFood {
        BundledFood(
            id: id, name: name, category: nil,
            per100g: Nutrition(energy: 370, protein: 13, carbohydrates: 60, fatTotal: 7),
            popularity: popularity, altNames: [], isIngredient: ingredient
        )
    }

    private func storedFood(_ name: String, in context: ModelContext) -> Food {
        let food = Food(name: name, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 200))
        context.insert(food)
        return food
    }

    // MARK: - Rung one: the whole line from memory

    @Test func aLineLoggedBeforeComesBackWholeWithoutSearching() async throws {
        let context = try makeContext()
        let oats = storedFood("Oats, rolled", in: context)
        let banana = storedFood("Banana, raw", in: context)
        try Phrase.remember(
            line: "oats with a banana",
            items: [
                PhraseDraftItem(name: "oats", amount: 40, food: oats),
                PhraseDraftItem(name: "banana", amount: 120, food: banana),
            ],
            in: context
        )
        // An empty repository, so anything that reaches a search finds nothing, and an
        // estimator that throws, so anything that reaches the model resolves to nothing.
        // Recall answering is the only way this test passes.
        let resolver = LineResolver(
            context: context, repository: FakeRepository(),
            estimator: FakeEstimator(failure: .failed("the model was asked"))
        )
        let resolution = await resolver.resolve("Banana and oats!")

        #expect(resolution.rows.count == 2)
        #expect(resolution.rows.allSatisfy { $0.origin == .phrase })
        #expect(resolution.rows.allSatisfy { $0.confidence == .settled })
        #expect(resolution.rows.map(\.amount) == [40, 120])
        #expect(resolution.canLog)
        // Nothing was checked because nothing needed checking.
        #expect(!resolution.wasChecked)
        #expect(resolution.glanceCount == 0)
    }

    @Test func aRecalledLineNeverAsksTheModel() async throws {
        // What keeps a repeat under five seconds: the fast path does not wait on a model.
        let context = try makeContext()
        let oats = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        // Both would throw if reached, so recall is the only thing that can answer.
        let validator = FakeValidator(failure: .cancelled)
        let resolver = LineResolver(
            context: context, repository: FakeRepository(), validator: validator,
            estimator: FakeEstimator(failure: .failed("the model was asked"))
        )
        let resolution = await resolver.resolve("oats")
        // A validator that throws on every call, and the line still resolves settled.
        #expect(resolution.rows.first?.confidence == .settled)
        #expect(!resolution.wasChecked)
    }

    // MARK: - Rung two: one familiar food in a new line

    @Test func aFamiliarFoodInsideANewLineComesFromHistory() async throws {
        let context = try makeContext()
        let oats = storedFood("Oats, rolled", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 45, food: oats)], in: context
        )
        let repository = FakeRepository(hits: ["banana": [bundled(2, "Banana, raw")]])
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats and banana")

        #expect(resolution.rows.count == 2)
        #expect(resolution.rows[0].origin == .item)
        #expect(resolution.rows[0].amount == 45)
        #expect(resolution.rows[1].origin == .database)
    }

    // MARK: - Rung three: the bundled tables

    @Test func anUnknownLineIsMatchedInTheTables() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.origin == .database)
        #expect(resolution.rows.first?.choice?.name == "Oats, rolled")
        #expect(resolution.rows.first?.confidence == .settled)
    }

    @Test func aFoodNothingMatchesBlocksTheLog() async throws {
        let context = try makeContext()
        let resolver = LineResolver(context: context, repository: FakeRepository(), estimator: FakeEstimator())
        let resolution = await resolver.resolve("something nobody has ever eaten")
        #expect(resolution.rows.count == 1)
        #expect(resolution.rows.first?.choice == nil)
        #expect(resolution.rows.first?.blocks == true)
        #expect(!resolution.canLog)
        #expect(resolution.blockingCount == 1)
    }

    @Test func anIngredientFormBlocksRatherThanSettling() async throws {
        // The coffee-powder case, with no model involved at all.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["coffee": [bundled(9, "Coffee, instant, powder", ingredient: true)]])
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let resolution = await resolver.resolve("coffee")
        #expect(resolution.rows.first?.confidence == .unsure)
        #expect(!resolution.canLog)
    }

    @Test func theModelsWeightIsTheAmount() async throws {
        // This read an amount off the front of the words — "200g rice" — which is what the
        // parser was for. The model reports a weight for everything it names, so the words
        // are its problem and the figure arrives already made.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "rice", lookupTerm: "rice", grams: 200)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let resolution = await resolver.resolve("200g rice")
        #expect(resolution.rows.first?.amount == 200)
    }

    @Test func theMealComesFromTheFoodsAndNotTheClock() async throws {
        // The reason the model is asked which meal it is: no clock can know that oats at
        // nine in the evening are breakfast.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "oats", lookupTerm: "oats", grams: 40)],
            meal: .breakfast
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.meal == .breakfast)
    }

    @Test func withNoModelNothingNewResolves() async throws {
        // The cost of one primary input. Search and the barcode scanner are how the app is
        // used when neither Apple Intelligence nor an endpoint will answer.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository, estimator: nil)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.isEmpty)
    }

    @Test func aModelThatFailsLeavesNothingRatherThanThrowing() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let estimator = FakeEstimator(failure: .failed("no network"))
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.isEmpty)
    }

    @Test func aFirstTimeFoodIsOfferedNoBucket() async throws {
        // "Usual" would mean nothing: there is no history to multiply.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.bucket == nil)
    }

    @Test func aRecalledFoodIsOfferedABucket() async throws {
        let context = try makeContext()
        let oats = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        let resolver = LineResolver(context: context, repository: FakeRepository(), estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.bucket == .usual)
    }

    // MARK: - Checking

    @Test func theModelCanMoveARowToAnotherCandidate() async throws {
        // The whole reason validation exists: "oat" retrieves the biscuits first and the
        // model moves it to the oats.
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            "oat": [bundled(5, "Biscuits, oat"), bundled(1, "Oats, rolled")],
        ])
        let validator = FakeValidator(verdicts: [
            MatchVerdict(item: 1, candidate: 1, certainty: .certain),
        ])
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oat")
        #expect(resolution.wasChecked)
        #expect(resolution.rows.first?.choice?.name == "Oats, rolled")
        #expect(resolution.rows.first?.confidence == .settled)
    }

    @Test func noneOfTheseLeavesTheRowBlocking() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(verdicts: [
            MatchVerdict(item: 1, candidate: 0, certainty: .unsure),
        ])
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.choice == nil)
        #expect(!resolution.canLog)
    }

    @Test func anIDOutsideTheShortlistReadsAsNoneRatherThanAsAHint() async throws {
        // The model can only ever pick a row a retriever found; it cannot name a food it
        // was not offered.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(verdicts: [
            MatchVerdict(item: 1, candidate: 4_242, certainty: .certain),
        ])
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.choice == nil)
    }

    @Test func probableFromTheModelCountsAsAGlance() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(verdicts: [
            MatchVerdict(item: 1, candidate: 1, certainty: .probable),
        ])
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.glanceCount == 1)
        #expect(resolution.canLog)
    }

    @Test func aValidatorThatFailsLeavesTheWholeLineUnchecked() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(failure: .unavailable("Apple Intelligence is off"))
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(!resolution.wasChecked)
        // The matcher's own reading stands, so the line is still usable.
        #expect(resolution.rows.first?.confidence == .settled)
        #expect(resolution.canLog)
    }

    @Test func aValidatorThatAnswersShortLeavesTheWholeLineUnchecked() async throws {
        // All-or-nothing, so "not checked" stays a property of the screen.
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            "oats": [bundled(1, "Oats, rolled")],
            "banana": [bundled(2, "Banana, raw")],
        ])
        let validator = FakeValidator(
            verdicts: [
                MatchVerdict(item: 1, candidate: 1, certainty: .certain),
                MatchVerdict(item: 2, candidate: 2, certainty: .certain),
            ],
            answerShort: true
        )
        let resolver = LineResolver(context: context, repository: repository, validator: validator, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats and banana")
        #expect(!resolution.wasChecked)
        #expect(resolution.rows.count == 2)
    }

    @Test func noValidatorIsAnOrdinaryConfigurationNotAFailure() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository, validator: nil, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats")
        #expect(!resolution.wasChecked)
        #expect(resolution.canLog)
    }

    // MARK: - Nothing to resolve

    @Test func aLineWithNoFoodInItResolvesToNothing() async throws {
        // The model found nothing to name. It used to be the parser that found nothing,
        // which is the same outcome reached by a different party.
        let context = try makeContext()
        let estimator = FakeEstimator(items: [])
        let resolver = LineResolver(context: context, repository: FakeRepository(), estimator: estimator)
        let resolution = await resolver.resolve("and some of my")
        #expect(resolution.isEmpty)
        #expect(!resolution.canLog)
    }

    @Test func aFailingSearchLeavesRowsUnmatchedRatherThanThrowing() async throws {
        let context = try makeContext()
        let repository = FakeRepository(failure: .databaseMissing)
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let resolution = await resolver.resolve("oats, banana")
        #expect(resolution.rows.count == 2)
        #expect(resolution.rows.allSatisfy { $0.choice == nil })
    }

    // MARK: - A term in the wording a table uses

    /// The report this came from: "a slice of Margherita pizza" showed as "pizza" with no
    /// food behind it. Measured against the real tables, a term written the way the prompt
    /// asks for it — with the commas a composition table uses — scored zero against the row
    /// of that very name, so the whole term was discarded and one of its words answered
    /// instead.
    @Test func aTermWrittenTheWayATableWritesOneStillMatches() async throws {
        let context = try makeContext()
        let margherita = bundled(11, "Pizza margherita (with tomato sauce, mozzarella)")
        let repository = FakeRepository(hits: ["Pizza, Margherita": [margherita]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "pizza", lookupTerm: "Pizza, Margherita", grams: 125)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("a slice of Margherita pizza").rows.first)
        #expect(row.choice?.name == "Pizza margherita (with tomato sauce, mozzarella)")
        #expect(!row.blocks)
    }

    /// The worse half of the same fault. "Cooked" names 390 rows in the real tables, and the
    /// cooked thing that ranked highest was fish — so "Pasta, cooked" and "Rice, cooked"
    /// were answered with *Fish, cooked (average)*, settled, with nothing asked of the user.
    /// A word saying how a food was prepared is not a food, and cannot answer for one.
    @Test func aPreparationWordNeverAnswersForAFood() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            // Nothing holds both words, which is what sends this down the fallback.
            "pasta": [bundled(21, "Pasta, cooked")],
            // Curated, as it is in the real tables, which is what let it win: the prior
            // took it from 0.691 to 0.887 against the word "cooked", above the 0.858 the
            // pasta row scores against "pasta".
            "cooked": [bundled(22, "Fish, cooked (average)", popularity: 23)],
        ])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "pasta", lookupTerm: "pasta, cooked", grams: 180)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("pasta").rows.first)
        #expect(row.choice?.name == "Pasta, cooked")
    }

    /// A narrowed match is the app answering a question nobody asked, so it is shown rather
    /// than assumed, however well the one word scored.
    @Test func aMatchFoundByNarrowingIsNeverSettled() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(31, "Oat flakes")]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "oats", lookupTerm: "oats, rolled", grams: 50)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("oats").rows.first)
        #expect(row.choice?.name == "Oat flakes")
        #expect(row.confidence == .probable)
        // Logged, not blocked: marked for a glance is the point of the middle tier.
        #expect(!row.blocks)
    }

    /// And a match on everything that was said still settles, so the cap above is about
    /// narrowing rather than about the tables being distrusted.
    @Test func aMatchOnTheWholeTermStillSettles() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oat flakes": [bundled(31, "Oat flakes")]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "oats", lookupTerm: "oat flakes", grams: 50)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("oats").rows.first)
        #expect(row.confidence == .settled)
    }

    // MARK: - What the fallback is allowed to look at

    /// Measured over a hundred written lines: the fallback used to try every word of a
    /// term, and a qualifier scores perfectly against rows that are a different food. This
    /// one answered with *Natural mineral water*, at 1.10, settled.
    @Test func aQualifierAfterACommaCannotAnswerForTheFood() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            "yogurt": [bundled(41, "Yogurt mild, min. 3.5 % fat", popularity: 80)],
            // Reachable only by searching the qualifier, which is now never searched.
            "natural": [bundled(42, "Natural mineral water", popularity: 60)],
        ])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "yogurt", lookupTerm: "yogurt, natural", grams: 150)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("yogurt").rows.first)
        #expect(row.choice?.name == "Yogurt mild, min. 3.5 % fat")
    }

    /// The same fault through a preposition: a pain au chocolat was logged as *Chocolate*,
    /// at 1.35, because the garnish outscored the pastry.
    @Test func aGarnishAfterAPrepositionCannotAnswerForTheFood() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            "croissant": [bundled(43, "Croissant (average)")],
            "chocolate": [bundled(44, "Chocolate", popularity: 100)],
        ])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "pain au chocolat", lookupTerm: "croissant with chocolate", grams: 70)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("pain au chocolat").rows.first)
        #expect(row.choice?.name == "Croissant (average)")
    }

    /// The head phrase entire is tried before any part of it, so the more specific answer
    /// wins where there is one. Searching the words alone gave *Bread, bagel* for rye bread.
    @Test func theHeadPhraseIsTriedWholeBeforeItsWords() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: [
            "rye bread": [bundled(45, "Rye bread", popularity: 87)],
            "bread": [bundled(46, "Bread, bagel")],
        ])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "toast", lookupTerm: "rye bread, toasted", grams: 50)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("toast").rows.first)
        #expect(row.choice?.name == "Rye bread")
    }

    /// A word has to answer what a row *is*. Prefix-matching the head is how "tonic water"
    /// came back as *Watermelon raw*, and there is no tonic row, so the honest answer is
    /// the one the sheet is built for: ask.
    @Test func aRowWhoseHeadMerelyBeginsWithTheWordIsNotAnAnswer() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["water": [bundled(47, "Watermelon raw", popularity: 40)]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "tonic water", lookupTerm: "tonic water", grams: 200)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("tonic water").rows.first)
        #expect(row.choice == nil)
        #expect(row.confidence == .unsure)
        #expect(row.blocks)
    }

    /// And when the head phrase finds nothing, nothing is what is reported. The words after
    /// the preposition are not consulted as a last resort, because that is where every one
    /// of the wrong answers came from.
    @Test func aHeadPhraseThatFindsNothingBlocksRatherThanGuessing() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["beef": [bundled(48, "Beef boiled", popularity: 70)]])
        let estimator = FakeEstimator(
            items: [EstimatedItem(name: "lasagne", lookupTerm: "lasagne with beef", grams: 350)]
        )
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("lasagne").rows.first)
        #expect(row.choice == nil)
        #expect(row.blocks)
    }

    // MARK: - What a step measures from

    @Test func aFoodEatenBeforeBringsItsOwnReference() async throws {
        // The stored row is where history lives. Without reading it, a food logged ten
        // times through the search screen reached this screen with the model's estimate
        // and no Less or More at all, because a search hit carries no past use of its own.
        let context = try makeContext()
        let stored = Food(name: "Rice, cooked", kind: .bundled, bundledID: 3, per100g: Nutrition(energy: 130))
        stored.lastGrams = 180
        context.insert(stored)
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let estimator = FakeEstimator(items: [EstimatedItem(name: "rice", lookupTerm: "rice", grams: 250)])
        let resolver = LineResolver(context: context, repository: repository, estimator: estimator)
        let row = try #require(await resolver.resolve("a big plate of rice").rows.first)

        // What was eaten today is the model's figure; what this person usually has is the
        // reference. Stepping down from a big plate has to mean less than usual.
        #expect(row.amount == 250)
        #expect(row.baseAmount == 180)
        #expect(row.canStep)
        #expect(row.stepped(to: .less).amount == AmountBucket.less.amount(of: 180))
    }

    @Test func aFoodNeverEatenOffersNoSteps() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let resolver = LineResolver(context: context, repository: repository, estimator: FakeEstimator())
        let row = try #require(await resolver.resolve("rice").rows.first)
        #expect(row.baseAmount == nil)
        #expect(!row.canStep)
    }

    // MARK: - Rung four: a product the tables do not hold

    @Test func aProductAnswersForAFoodTheTablesDoNotHold() async throws {
        let context = try makeContext()
        let jar = FoodChoice(
            source: .product(foodID: UUID()), name: "Calvé Peanut Butter",
            perUnit: Nutrition(energy: 620), lastAmount: nil
        )
        let resolver = LineResolver(
            context: context, repository: FakeRepository(),
            products: { _ in [jar] }, estimator: FakeEstimator()
        )
        let row = try #require(await resolver.resolve("calvé peanut butter").rows.first)
        #expect(row.origin == .product)
        #expect(row.choice?.name == "Calvé Peanut Butter")
        // Logged and marked for a glance, never settled: nothing has checked a stranger's
        // entry, and the row says "Matched by name, Open Food Facts" whatever was true of
        // the rest of the line.
        #expect(row.confidence == .probable)
        #expect(row.origin.detail(checked: true) == "Matched by name, Open Food Facts")
    }

    @Test func theTablesAreAlwaysTriedBeforeAProduct() async throws {
        // Offline, licence-clean and measured first; a crowdsourced record only when there
        // is nothing better. A products closure that fails the test if it is reached.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oat flakes")]])
        let resolver = LineResolver(
            context: context, repository: repository,
            products: { _ in Issue.record("the product rung was asked"); return [] },
            estimator: FakeEstimator()
        )
        let row = try #require(await resolver.resolve("oats").rows.first)
        #expect(row.origin == .database)
    }

    @Test func withoutTheOptInNoProductIsAsked() async throws {
        // `nil` rather than an empty answer: the opt-in is off, so nothing may be asked at
        // all, and an unmatched food goes to the user exactly as it did before.
        let context = try makeContext()
        let resolver = LineResolver(
            context: context, repository: FakeRepository(), products: nil, estimator: FakeEstimator()
        )
        let row = try #require(await resolver.resolve("calvé peanut butter").rows.first)
        #expect(row.choice == nil)
        #expect(row.blocks)
    }
}
