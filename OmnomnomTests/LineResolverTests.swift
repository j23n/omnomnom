import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// What a line comes to without a model reading it, and the search that offers a row the
/// other foods it could have been.
///
/// Two things resolve a line now. A whole line logged before comes back from memory, which
/// is in front of everything; anything else is read by a driving model, which
/// `LineResolverToolsTests` covers, and resolves to nothing where there is no model to ask.
/// Between them there used to be a ladder that guessed at the wording a composition table
/// uses and searched on the guess.
///
/// The search that ladder was built around survives, because the sheet still offers the
/// alternatives to a row's food — and `candidates(for:)` is its only door. So the
/// narrowing, the head-phrase rules and the reference a food brings from history are
/// asserted here on the shortlist it answers with, best first, rather than on a row a
/// retriever built from it.
struct LineResolverTests {
    private func bundled(_ id: Int, _ name: String, popularity: Int = 0) -> BundledFood {
        BundledFood(
            id: id, name: name, category: nil,
            per100g: Nutrition(energy: 370, protein: 13, carbohydrates: 60, fatTotal: 7),
            popularity: popularity, altNames: []
        )
    }

    private func storedFood(_ name: String, in context: ModelContext) -> Food {
        let food = Food(name: name, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 200))
        context.insert(food)
        return food
    }

    // MARK: - The whole line from memory

    @Test func aLineLoggedBeforeComesBackWholeWithoutSearching() async throws {
        let context = try TestStore.context()
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
        // An empty repository, so anything that reaches a search finds nothing, and a
        // driver that throws, so anything that reaches the model resolves to nothing.
        // Recall answering is the only way this test passes.
        let driver = FakeDriver()
        driver.failure = .failed("the model was asked")
        let resolver = LineResolver(context: context, repository: FakeRepository(), driver: driver)
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
        let context = try TestStore.context()
        let oats = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        // A driver that throws on every call, so recall is the only thing that can answer.
        let driver = FakeDriver()
        driver.failure = .failed("the model was asked")
        let resolver = LineResolver(context: context, repository: FakeRepository(), driver: driver)
        let resolution = await resolver.resolve("oats")

        #expect(driver.asked == 0)
        #expect(resolution.rows.first?.confidence == .settled)
        #expect(!resolution.wasChecked)
    }

    /// A remembered amount is this person's usual by definition — they logged it — so the
    /// row arrives with the step it was last stored under, and Less and More have something
    /// to multiply. Recall is the only path that still hands a row one: a food a model
    /// chose today carries a reference but no step.
    @Test func aRecalledFoodIsOfferedABucket() async throws {
        let context = try TestStore.context()
        let oats = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        let resolver = LineResolver(context: context, repository: FakeRepository())
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.bucket == .usual)
    }

    // MARK: - Nothing to resolve

    @Test func withNoModelNothingNewResolves() async throws {
        // The cost of one primary input. Search and the barcode scanner are how the app is
        // used when neither Apple Intelligence nor an endpoint will answer.
        let context = try TestStore.context()
        // The tables hold the food, and it makes no difference: nothing searches them on
        // behalf of a line any more, so without a model the row is out of reach.
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.isEmpty)
    }

    @Test func aLineWithNoFoodInItResolvesToNothing() async throws {
        // The model read the line and named nothing in it. That is not a failure and there
        // is nothing for the user to go and fix, so no sentence is offered with the empty
        // resolution — the composer's own copy covers a line of filler words.
        let context = try TestStore.context()
        let driver = FakeDriver()
        let resolver = LineResolver(context: context, repository: FakeRepository(), driver: driver)
        let resolution = await resolver.resolve("and some of my")

        #expect(resolution.isEmpty)
        #expect(!resolution.canLog)
        #expect(resolution.failure == nil)
    }

    @Test func aFailingSearchAnswersWithNothingRatherThanThrowing() async throws {
        // A database that cannot be opened is not something the user can act on while
        // reading a list of alternatives, so the list is empty and the row keeps the food
        // it already has.
        let context = try TestStore.context()
        let repository = FakeRepository(failure: .databaseMissing)
        let resolver = LineResolver(context: context, repository: repository)
        #expect(await resolver.candidates(for: "oats, banana").isEmpty)
    }

    // MARK: - A term in the wording a table uses

    /// The report this came from: "a slice of Margherita pizza" showed as "pizza" with no
    /// food behind it. Measured against the real tables, a term written the way a
    /// composition table writes one — with the commas — scored zero against the row of that
    /// very name, so the whole term was discarded and one of its words answered instead.
    @Test func aTermWrittenTheWayATableWritesOneStillMatches() async throws {
        let context = try TestStore.context()
        let margherita = bundled(11, "Pizza margherita (with tomato sauce, mozzarella)")
        let repository = FakeRepository(hits: ["Pizza, Margherita": [margherita]])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "Pizza, Margherita").first)
        #expect(best.name == "Pizza margherita (with tomato sauce, mozzarella)")
    }

    /// The worse half of the same fault. "Cooked" names 390 rows in the real tables, and the
    /// cooked thing that ranked highest was fish — so "Pasta, cooked" and "Rice, cooked"
    /// were answered with *Fish, cooked (average)*, settled, with nothing asked of the user.
    /// A word saying how a food was prepared is not a food, and cannot answer for one.
    @Test func aPreparationWordNeverAnswersForAFood() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: [
            // Nothing holds both words, which is what sends this down the fallback.
            "pasta": [bundled(21, "Pasta, cooked")],
            // Curated, as it is in the real tables, which is what let it win: the prior
            // took it from 0.691 to 0.887 against the word "cooked", above the 0.858 the
            // pasta row scores against "pasta".
            "cooked": [bundled(22, "Fish, cooked (average)", popularity: 23)],
        ])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "pasta, cooked").first)
        #expect(best.name == "Pasta, cooked")
    }

    /// Narrowing is what reaches a table that words a food differently: nothing holds both
    /// words of "oats, rolled", and the head alone finds the flakes.
    @Test func aNarrowedTermStillFindsTheFood() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: ["oats": [bundled(31, "Oat flakes")]])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "oats, rolled").first)
        #expect(best.name == "Oat flakes")
    }

    /// And a term that answers whole is kept whole, so the narrowing stays a rescue for a
    /// dead end rather than a second opinion on a term that worked.
    @Test func aMatchOnTheWholeTermBeatsANarrowedOne() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: [
            "oat flakes": [bundled(31, "Oat flakes")],
            // Curated, and what the head word on its own would have answered with. Never
            // reached: the whole term answered, so no part of it is searched.
            "oat": [bundled(32, "Oat milk", popularity: 90)],
        ])
        let resolver = LineResolver(context: context, repository: repository)
        let choices = await resolver.candidates(for: "oat flakes")

        #expect(choices.first?.name == "Oat flakes")
        #expect(!choices.contains(where: { $0.name == "Oat milk" }))
    }

    // MARK: - What the fallback is allowed to look at

    /// Measured over a hundred written lines: the fallback used to try every word of a
    /// term, and a qualifier scores perfectly against rows that are a different food. This
    /// one answered with *Natural mineral water*, at 1.10, settled.
    @Test func aQualifierAfterACommaCannotAnswerForTheFood() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: [
            "yogurt": [bundled(41, "Yogurt mild, min. 3.5 % fat", popularity: 80)],
            // Reachable only by searching the qualifier, which is now never searched.
            "natural": [bundled(42, "Natural mineral water", popularity: 60)],
        ])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "yogurt, natural").first)
        #expect(best.name == "Yogurt mild, min. 3.5 % fat")
    }

    /// The same fault through a preposition: a pain au chocolat was logged as *Chocolate*,
    /// at 1.35, because the garnish outscored the pastry.
    @Test func aGarnishAfterAPrepositionCannotAnswerForTheFood() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: [
            "croissant": [bundled(43, "Croissant (average)")],
            "chocolate": [bundled(44, "Chocolate", popularity: 100)],
        ])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "croissant with chocolate").first)
        #expect(best.name == "Croissant (average)")
    }

    /// The head phrase entire is tried before any part of it, so the more specific answer
    /// wins where there is one. Searching the words alone gave *Bread, bagel* for rye bread.
    @Test func theHeadPhraseIsTriedWholeBeforeItsWords() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: [
            "rye bread": [bundled(45, "Rye bread", popularity: 87)],
            "bread": [bundled(46, "Bread, bagel")],
        ])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "rye bread, toasted").first)
        #expect(best.name == "Rye bread")
    }

    /// A word has to answer what a row *is*. Prefix-matching the head is how "tonic water"
    /// came back as *Watermelon raw*, and there is no tonic row — so nothing is the honest
    /// answer, and the sheet asks rather than offering a melon.
    @Test func aRowWhoseHeadMerelyBeginsWithTheWordIsNotAnAnswer() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: ["water": [bundled(47, "Watermelon raw", popularity: 40)]])
        let resolver = LineResolver(context: context, repository: repository)
        #expect(await resolver.candidates(for: "tonic water").isEmpty)
    }

    /// And when the head phrase finds nothing, nothing is what comes back. The words after
    /// the preposition are not consulted as a last resort, because that is where every one
    /// of the wrong answers came from.
    @Test func aHeadPhraseThatFindsNothingAnswersWithNothing() async throws {
        let context = try TestStore.context()
        let repository = FakeRepository(hits: ["beef": [bundled(48, "Beef boiled", popularity: 70)]])
        let resolver = LineResolver(context: context, repository: repository)
        #expect(await resolver.candidates(for: "lasagne with beef").isEmpty)
    }

    // MARK: - What a step measures from

    @Test func aFoodEatenBeforeBringsItsOwnReference() async throws {
        // The stored row is where history lives, and a table row carries none of its own:
        // without reading it, a food logged ten times through the search screen reached
        // the sheet with no Less or More at all. What a step multiplies is this figure.
        let context = try TestStore.context()
        let stored = Food(name: "Rice, cooked", kind: .bundled, bundledID: 3, per100g: Nutrition(energy: 130))
        stored.lastGrams = 180
        context.insert(stored)
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "rice").first)

        #expect(best.name == "Rice, cooked")
        #expect(best.lastAmount == 180)
    }

    @Test func aFoodNeverEatenOffersNoSteps() async throws {
        // Nothing to multiply, so the steps are absent rather than meaningless: "usual" has
        // to mean this person's usual, and a food they have never had has no usual.
        let context = try TestStore.context()
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let resolver = LineResolver(context: context, repository: repository)
        let best = try #require(await resolver.candidates(for: "rice").first)
        #expect(best.lastAmount == nil)
    }
}
