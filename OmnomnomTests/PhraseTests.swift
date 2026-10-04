import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// Remembering what a line resolved to, against an in-memory store with the app's schema.
struct PhraseTests {
    private func makeContext() throws -> ModelContext {
        let schema = StoreSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func food(_ name: String, in context: ModelContext) -> Food {
        let food = Food(name: name, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 100))
        context.insert(food)
        return food
    }

    // MARK: - The shape of recall

    @Test func aLineComesBackWithItsFoodsAndItsAmounts() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        let banana = food("Banana", in: context)
        try Phrase.remember(
            line: "oats with a banana",
            items: [
                PhraseDraftItem(name: "oats", amount: 40, food: oats),
                PhraseDraftItem(name: "banana", amount: 120, food: banana),
            ],
            in: context
        )

        // Typed differently, and it still lands.
        let recalled = try #require(try Phrase.recall("Banana and oats!", in: context))
        #expect(recalled.orderedItems.map(\.name) == ["oats", "banana"])
        #expect(recalled.orderedItems.map(\.amount) == [40, 120])
        #expect(recalled.orderedItems.map(\.food?.name) == ["Oats", "Banana"])
    }

    @Test func itemsComeBackInTheOrderTheyWereLogged() throws {
        let context = try makeContext()
        let items = (1...4).map { index in
            PhraseDraftItem(name: "item \(index)", amount: Double(index), food: food("f\(index)", in: context))
        }
        try Phrase.remember(line: "a b c d", items: items, in: context)
        let recalled = try #require(try Phrase.recall("d c b a", in: context))
        #expect(recalled.orderedItems.map(\.sortIndex) == [0, 1, 2, 3])
        #expect(recalled.orderedItems.map(\.name) == ["item 1", "item 2", "item 3", "item 4"])
    }

    @Test func aSingleWordPhraseIsASynonymForAFood() throws {
        // The same table serves the alias case: one word, one item.
        let context = try makeContext()
        let coffee = food("Coffee with milk", in: context)
        try Phrase.remember(
            line: "flat white",
            items: [PhraseDraftItem(name: "flat white", amount: 200, food: coffee)],
            in: context
        )
        let recalled = try #require(try Phrase.recall("Flat White", in: context))
        #expect(recalled.orderedItems.count == 1)
        #expect(recalled.orderedItems.first?.food?.name == "Coffee with milk")
    }

    @Test func nothingIsRecalledForALineNeverTyped() throws {
        let context = try makeContext()
        #expect(try Phrase.recall("something nobody has eaten", in: context) == nil)
    }

    // MARK: - Writing

    @Test func rememberingAgainReplacesRatherThanAccumulates() throws {
        let context = try makeContext()
        let wrong = food("Oat biscuits", in: context)
        let right = food("Oats, rolled", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 30, food: wrong)], in: context
        )
        // The user corrects the row, which rewrites what the phrase means.
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 45, food: right)], in: context
        )
        let recalled = try #require(try Phrase.recall("oats", in: context))
        #expect(recalled.orderedItems.count == 1)
        #expect(recalled.orderedItems.first?.food?.name == "Oats, rolled")
        #expect(recalled.orderedItems.first?.amount == 45)
        #expect(try Phrase.all(in: context).count == 1)
    }

    @Test func rememberingKeepsOneRowPerKeyHoweverItIsTyped() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        for line in ["oats and banana", "banana with oats", "Banana, oats"] {
            try Phrase.remember(
                line: line, items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
            )
        }
        #expect(try Phrase.all(in: context).count == 1)
        // The display text is the last wording used, while the key is what matched.
        #expect(try Phrase.all(in: context).first?.text == "Banana, oats")
    }

    @Test func useCountAndLastUsedTrackWriting() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        let draft = [PhraseDraftItem(name: "oats", amount: 40, food: oats)]
        let early = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        try Phrase.remember(line: "oats", items: draft, in: context, now: early)
        let phrase = try #require(try Phrase.remember(line: "oats", items: draft, in: context, now: later))
        #expect(phrase.useCount == 2)
        #expect(phrase.lastUsed == later)
    }

    @Test func aLineWithNoKeyIsNotRemembered() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        let written = try Phrase.remember(
            line: "and some of my", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        #expect(written == nil)
        #expect(try Phrase.all(in: context).isEmpty)
    }

    @Test func aPhraseWithNoItemsIsNotRemembered() throws {
        let context = try makeContext()
        #expect(try Phrase.remember(line: "oats", items: [], in: context) == nil)
        #expect(try Phrase.all(in: context).isEmpty)
    }

    // MARK: - When the memory can no longer be trusted

    @Test func aPhraseWhoseFoodWasDeletedIsNotRecalled() throws {
        // Half a meal recalled silently is worse than being asked again.
        let context = try makeContext()
        let oats = food("Oats", in: context)
        let banana = food("Banana", in: context)
        try Phrase.remember(
            line: "oats and banana",
            items: [
                PhraseDraftItem(name: "oats", amount: 40, food: oats),
                PhraseDraftItem(name: "banana", amount: 120, food: banana),
            ],
            in: context
        )
        context.delete(banana)
        try context.save()
        #expect(try Phrase.recall("oats and banana", in: context) == nil)
    }

    @Test func deletingAFoodDoesNotDeleteThePhrase() throws {
        // Nullify, not cascade: the line survives and can be written over.
        let context = try makeContext()
        let oats = food("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context
        )
        context.delete(oats)
        try context.save()
        #expect(try Phrase.all(in: context).count == 1)

        // And logging the line again makes it recallable once more.
        let replacement = food("Oats, rolled", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: replacement)], in: context
        )
        #expect(try Phrase.recall("oats", in: context) != nil)
        #expect(try Phrase.all(in: context).count == 1)
    }

    @Test func allIsOrderedByMostRecentlyUsed() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        let draft = [PhraseDraftItem(name: "oats", amount: 40, food: oats)]
        try Phrase.remember(line: "first", items: draft, in: context, now: Date(timeIntervalSince1970: 1_000))
        try Phrase.remember(line: "second", items: draft, in: context, now: Date(timeIntervalSince1970: 2_000))
        #expect(try Phrase.all(in: context).map(\.text) == ["second", "first"])
    }

    @Test func recallingNotesTheUseWithoutRewritingTheItems() throws {
        let context = try makeContext()
        let oats = food("Oats", in: context)
        try Phrase.remember(
            line: "oats", items: [PhraseDraftItem(name: "oats", amount: 40, food: oats)], in: context,
            now: Date(timeIntervalSince1970: 1_000)
        )
        let phrase = try #require(try Phrase.recall("oats", in: context))
        phrase.noteRecalled(at: Date(timeIntervalSince1970: 5_000))
        #expect(phrase.useCount == 2)
        #expect(phrase.lastUsed == Date(timeIntervalSince1970: 5_000))
        #expect(phrase.orderedItems.map(\.amount) == [40])
    }
}
