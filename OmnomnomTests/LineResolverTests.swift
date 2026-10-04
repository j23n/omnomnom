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

/// The four rungs, in order, and what happens when the model is absent or wrong.
struct LineResolverTests {
    private func makeContext() throws -> ModelContext {
        let schema = StoreSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func bundled(_ id: Int, _ name: String, ingredient: Bool = false) -> BundledFood {
        BundledFood(
            id: id, name: name, category: nil,
            per100g: Nutrition(energy: 370, protein: 13, carbohydrates: 60, fatTotal: 7),
            popularity: 0, altNames: [], isIngredient: ingredient
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
        // An empty repository, so anything that reaches a search finds nothing.
        let resolver = LineResolver(context: context, repository: FakeRepository())
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
        let validator = FakeValidator(failure: .cancelled)
        let resolver = LineResolver(context: context, repository: FakeRepository(), validator: validator)
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
        let resolver = LineResolver(context: context, repository: repository)
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
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.origin == .database)
        #expect(resolution.rows.first?.choice?.name == "Oats, rolled")
        #expect(resolution.rows.first?.confidence == .settled)
    }

    @Test func aFoodNothingMatchesBlocksTheLog() async throws {
        let context = try makeContext()
        let resolver = LineResolver(context: context, repository: FakeRepository())
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
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("coffee")
        #expect(resolution.rows.first?.confidence == .unsure)
        #expect(!resolution.canLog)
    }

    @Test func anExplicitAmountInTheLineWins() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["rice": [bundled(3, "Rice, cooked")]])
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("200g rice")
        #expect(resolution.rows.first?.amount == 200)
    }

    @Test func aFirstTimeFoodIsOfferedNoBucket() async throws {
        // "Usual" would mean nothing: there is no history to multiply.
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.bucket == nil)
    }

    @Test func aRecalledFoodIsOfferedABucket() async throws {
        let context = try makeContext()
        let oats = storedFood("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        let resolver = LineResolver(context: context, repository: FakeRepository())
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
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
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
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
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
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.rows.first?.choice == nil)
    }

    @Test func probableFromTheModelCountsAsAGlance() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(verdicts: [
            MatchVerdict(item: 1, candidate: 1, certainty: .probable),
        ])
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
        let resolution = await resolver.resolve("oats")
        #expect(resolution.glanceCount == 1)
        #expect(resolution.canLog)
    }

    @Test func aValidatorThatFailsLeavesTheWholeLineUnchecked() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let validator = FakeValidator(failure: .unavailable("Apple Intelligence is off"))
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
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
        let resolver = LineResolver(context: context, repository: repository, validator: validator)
        let resolution = await resolver.resolve("oats and banana")
        #expect(!resolution.wasChecked)
        #expect(resolution.rows.count == 2)
    }

    @Test func noValidatorIsAnOrdinaryConfigurationNotAFailure() async throws {
        let context = try makeContext()
        let repository = FakeRepository(hits: ["oats": [bundled(1, "Oats, rolled")]])
        let resolver = LineResolver(context: context, repository: repository, validator: nil)
        let resolution = await resolver.resolve("oats")
        #expect(!resolution.wasChecked)
        #expect(resolution.canLog)
    }

    // MARK: - Nothing to resolve

    @Test func aLineWithNoFoodResolvesToNothing() async throws {
        let context = try makeContext()
        let resolver = LineResolver(context: context, repository: FakeRepository())
        let resolution = await resolver.resolve("and some of my")
        #expect(resolution.isEmpty)
        #expect(!resolution.canLog)
    }

    @Test func aFailingSearchLeavesRowsUnmatchedRatherThanThrowing() async throws {
        let context = try makeContext()
        let repository = FakeRepository(failure: .databaseMissing)
        let resolver = LineResolver(context: context, repository: repository)
        let resolution = await resolver.resolve("oats, banana")
        #expect(resolution.rows.count == 2)
        #expect(resolution.rows.allSatisfy { $0.choice == nil })
    }
}
