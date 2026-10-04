import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// A line someone eats by default, offered rather than assumed.
struct BaselinePhraseTests {
    private func makeContext() throws -> ModelContext {
        let schema = StoreSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func phrase(
        _ line: String, in context: ModelContext, uses: Int = 1, slot: MealSlot? = nil
    ) throws -> Phrase {
        let food = Food(name: line, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 100))
        context.insert(food)
        var written: Phrase?
        for _ in 0..<uses {
            written = try Phrase.remember(
                line: line, items: [PhraseDraftItem(name: line, amount: 40, food: food)],
                in: context, slot: slot
            )
        }
        return try #require(written)
    }

    @Test func aSlotHasNoBaselineUntilOneIsSet() throws {
        let context = try makeContext()
        #expect(try BaselinePhrase.baseline(for: .breakfast, in: context) == nil)
    }

    @Test func settingOneStoresItForThatSlotOnly() throws {
        let context = try makeContext()
        let oats = try phrase("oats and banana", in: context)
        try BaselinePhrase.set(oats, for: .breakfast, in: context)
        #expect(try BaselinePhrase.baseline(for: .breakfast, in: context)?.phrase?.id == oats.id)
        #expect(try BaselinePhrase.baseline(for: .lunch, in: context) == nil)
    }

    @Test func settingAgainReplacesRatherThanAccumulating() throws {
        let context = try makeContext()
        let first = try phrase("oats", in: context)
        let second = try phrase("toast", in: context)
        try BaselinePhrase.set(first, for: .breakfast, in: context)
        try BaselinePhrase.set(second, for: .breakfast, in: context)
        #expect(try BaselinePhrase.all(in: context).count == 1)
        #expect(try BaselinePhrase.baseline(for: .breakfast, in: context)?.phrase?.id == second.id)
    }

    @Test func aBaselineIsOfferableUntilItIsDeclined() throws {
        let context = try makeContext()
        let oats = try phrase("oats", in: context)
        let baseline = try BaselinePhrase.set(oats, for: .breakfast, in: context)
        #expect(baseline.isOfferable)
        baseline.declinedAt = .now
        #expect(!baseline.isOfferable)
    }

    @Test func settingAgainUndoesADecline() throws {
        // Asking again is how the user gets the offer back.
        let context = try makeContext()
        let oats = try phrase("oats", in: context)
        let baseline = try BaselinePhrase.set(oats, for: .breakfast, in: context)
        baseline.declinedAt = .now
        try BaselinePhrase.set(oats, for: .breakfast, in: context)
        #expect(baseline.isOfferable)
    }

    @Test func aBaselineWhoseFoodWentIsNotOffered() throws {
        let context = try makeContext()
        let oats = try phrase("oats", in: context)
        let baseline = try BaselinePhrase.set(oats, for: .breakfast, in: context)
        for item in oats.orderedItems {
            if let food = item.food { context.delete(food) }
        }
        try context.save()
        #expect(!baseline.isOfferable)
    }

    @Test func clearingForgetsItEntirely() throws {
        let context = try makeContext()
        let oats = try phrase("oats", in: context)
        try BaselinePhrase.set(oats, for: .breakfast, in: context)
        try BaselinePhrase.clear(for: .breakfast, in: context)
        #expect(try BaselinePhrase.baseline(for: .breakfast, in: context) == nil)
    }

    // MARK: - What to suggest

    @Test func aLineLoggedEnoughTimesInASlotIsSuggested() throws {
        let context = try makeContext()
        _ = try phrase("oats and banana", in: context, uses: BaselinePhrase.suggestionThreshold, slot: .breakfast)
        #expect(try BaselinePhrase.suggestion(for: .breakfast, in: context)?.text == "oats and banana")
    }

    @Test func aLineLoggedTooFewTimesIsNotSuggested() throws {
        // Three is a coincidence; a fortnight of weekdays is five.
        let context = try makeContext()
        _ = try phrase("oats", in: context, uses: BaselinePhrase.suggestionThreshold - 1, slot: .breakfast)
        #expect(try BaselinePhrase.suggestion(for: .breakfast, in: context) == nil)
    }

    @Test func aSuggestionIsScopedToItsSlot() throws {
        let context = try makeContext()
        _ = try phrase("oats", in: context, uses: BaselinePhrase.suggestionThreshold, slot: .breakfast)
        #expect(try BaselinePhrase.suggestion(for: .dinner, in: context) == nil)
    }

    @Test func theMostLoggedLineWins() throws {
        let context = try makeContext()
        _ = try phrase("oats", in: context, uses: BaselinePhrase.suggestionThreshold, slot: .breakfast)
        _ = try phrase("toast", in: context, uses: BaselinePhrase.suggestionThreshold + 3, slot: .breakfast)
        #expect(try BaselinePhrase.suggestion(for: .breakfast, in: context)?.text == "toast")
    }

    @Test func rememberingRecordsTheSlotItWasLoggedIn() throws {
        let context = try makeContext()
        let written = try phrase("oats", in: context, slot: .breakfast)
        #expect(written.lastSlot == .breakfast)
    }
}
