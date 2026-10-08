import Foundation
import Testing
@testable import Omnomnom

/// The mark: what it says, what it asks, and what a correction keeps.
struct GuessedMatchTests {
    private func entry(
        _ name: String = "Oat flakes", wording: String? = nil, guessed: Bool = false,
        amount: Double = 45, measure: FoodMeasure = .mass, servings: Double? = nil
    ) -> LogEntry {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_767_254_400),
            mealSlot: .breakfast,
            foodName: name,
            amount: RawAmount(amount, measure: measure),
            snapshot: Nutrition(energy: 167),
            measure: measure
        )
        entry.wording = wording
        entry.guessed = guessed
        entry.servings = servings
        return entry
    }

    private func choice(_ name: String, last: Double? = nil, measure: FoodMeasure = .mass) -> FoodChoice {
        FoodChoice(
            source: .bundled(id: abs(name.hashValue % 10_000)),
            name: name,
            perUnit: Nutrition(energy: 372),
            measure: measure,
            lastAmount: last
        )
    }

    // MARK: - What a new entry carries

    @Test func anEntryIsUnmarkedAndWordlessUntilSomethingSaysOtherwise() {
        // Every entry logged before any of this existed reads this way, which is what it
        // should read: nobody guessed it, and nothing knows what was said.
        let fresh = entry()
        #expect(!fresh.guessed)
        #expect(fresh.wording == nil)
    }

    // MARK: - The mark on the row

    @Test func theMarkQuotesWhatWasSaid() {
        #expect(EntryRow.markText(for: entry(wording: "oats", guessed: true)) == "Matched from “oats”")
    }

    @Test func aLineWithNoWordsOfItsOwnStillSaysWhoChose() {
        // A widget tap and a photo both log without anything being typed. The row cannot
        // quote a word, and it must not pretend the user named the food either.
        #expect(EntryRow.markText(for: entry(guessed: true)) == "Matched for you")
        #expect(EntryRow.markText(for: entry(wording: "", guessed: true)) == "Matched for you")
    }

    // MARK: - The question

    @Test func theQuestionIsAskedInThePersonsOwnWords() {
        #expect(GuessedMatchSheet.question(for: entry(wording: "oats", guessed: true)) == "You said “oats”")
        #expect(GuessedMatchSheet.question(for: entry(guessed: true)) == "Logged as")
    }

    @Test func theQuestionIsAskedAgainstWhatIsActuallyInTheDay() {
        let detail = GuessedMatchSheet.loggedDetail(of: entry(amount: 45))
        #expect(detail.hasPrefix("45 g · "))
        // The time is the entry's, not now: an answer given at midnight is about a
        // breakfast.
        #expect(detail.contains(":"))
    }

    @Test func aRecipeEntrySaysItsServingsFirst() {
        let detail = GuessedMatchSheet.loggedDetail(of: entry(amount: 351, servings: 1.5))
        #expect(detail.hasPrefix("1.5 servings · 351 g"))
    }

    // MARK: - What a correction logs

    @Test func theNumberOnTheRowIsTheNumberLogged() {
        // 45 of what it turned out to be, not 45 per cent of anything and not 100 g.
        #expect(EntryLogger.amount(replacing: entry(amount: 45), with: choice("Oat bran")) == 45)
    }

    @Test func aFoodsOwnHistoryDoesNotOverrideWhatIsOnTheRow() {
        // The amount is a fact about this meal. What this person usually has of the new
        // food is a fact about other meals, and it does not get to rewrite this one.
        #expect(EntryLogger.amount(replacing: entry(amount: 45), with: choice("Oat bran", last: 200)) == 45)
    }

    @Test func aRecipeFallsBackToWhatWasLastHadOfIt() {
        let recipe = FoodChoice(
            source: .recipe(id: UUID()), name: "Porridge", perUnit: Nutrition(energy: 90),
            amountPerServing: RawAmount(250, measure: .mass), lastAmount: 2
        )
        #expect(EntryLogger.amount(replacing: entry(amount: 250), with: recipe) == 2)
    }

    @Test func aRecipeNeverHadIsOneServing() {
        let recipe = FoodChoice(
            source: .recipe(id: UUID()), name: "Porridge", perUnit: Nutrition(energy: 90),
            amountPerServing: RawAmount(250, measure: .mass)
        )
        #expect(EntryLogger.amount(replacing: entry(amount: 250), with: recipe) == 1)
    }

    @Test func leavingARecipeForAFoodDoesNotLogThatManyGrams() {
        // 1.5 servings is not 1.5 g of anything. Nothing on the row survives that change
        // of unit, so the new food's own history answers instead.
        let row = entry("Porridge", amount: 375, servings: 1.5)
        #expect(EntryLogger.amount(replacing: row, with: choice("Oat flakes", last: 45)) == 45)
        #expect(
            EntryLogger.amount(replacing: row, with: choice("Oat flakes"))
                == Formatters.defaultAmount
        )
    }

    @Test func anEntryWithNoAmountAtAllFallsBackRatherThanLoggingNothing() {
        #expect(
            EntryLogger.amount(replacing: entry(amount: 0), with: choice("Oat flakes"))
                == Formatters.defaultAmount
        )
    }
}
