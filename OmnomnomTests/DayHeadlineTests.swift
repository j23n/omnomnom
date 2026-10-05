import Foundation
import Testing
@testable import Omnomnom

/// The sentence at the top of Today, and the line under it.
struct DayHeadlineTests {
    @Test func theCountIsNamedAndNeverDivided() {
        #expect(DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]).sentence == "3 of 4 meals")
        #expect(DayAnswers(logged: [.breakfast]).sentence == "1 of 4 meals")
    }

    @Test func anEmptyDayAndAFullOneBothSaySoInWords() {
        #expect(DayAnswers.empty.sentence == "No meals yet")
        #expect(DayAnswers(logged: Set(MealSlot.allCases)).sentence == "All 4 meals")
    }

    @Test func aSkippedMealIsAnAnswerLikeAnyOther() {
        // The point of storing a skipped slot: "nothing tonight" closes dinner.
        #expect(DayAnswers(logged: [], skipped: Set(MealSlot.allCases)).sentence == "All 4 meals")
    }

    @Test func noPercentageAnywhere() {
        for answers in [
            DayAnswers.empty,
            DayAnswers(logged: [.breakfast]),
            DayAnswers(logged: [.breakfast, .lunch, .dinner]),
            DayAnswers(logged: Set(MealSlot.allCases))
        ] {
            #expect(!answers.sentence.contains("%"))
            #expect(!answers.sentence.contains("per cent"))
        }
    }

    // MARK: - The line under it

    @Test func whatIsOwedIsNamedRatherThanCounted() {
        // "breakfast and dinner" is something to act on; "2 unanswered" is only a score.
        let answers = DayAnswers(logged: [.lunch], skipped: [.snack])
        #expect(DayHeadline.note(answers: answers, isAssumed: false) == "Still to answer: breakfast and dinner")
    }

    @Test func oneMealOwedReadsAsOne() {
        let answers = DayAnswers(logged: [.breakfast, .lunch, .dinner])
        #expect(DayHeadline.note(answers: answers, isAssumed: false) == "Still to answer: snack")
    }

    @Test func aClosedDaySaysThereIsNothingLeft() {
        let answers = DayAnswers(logged: Set(MealSlot.allCases))
        #expect(DayHeadline.note(answers: answers, isAssumed: false) == "Nothing left to answer")
    }

    @Test func aDayTakenFromTheUsualOneSaysWhereItCameFrom() {
        // Ahead of what is owed, because where the day came from is the more important
        // fact about it: nothing on it was described.
        let answers = DayAnswers(logged: [.breakfast])
        #expect(DayHeadline.note(answers: answers, isAssumed: true) == "Taken from your usual day")
    }

    @Test func theMealsAreNamedInTheOrderTheyAreEaten() throws {
        // Never in the order the set happens to iterate in, which is nobody's day. The
        // list itself is the system's, so this checks the order rather than the commas:
        // whether the last one takes one is a question about English, not about this app.
        let note = DayHeadline.note(answers: .empty, isAssumed: false)
        let positions = try ["breakfast", "lunch", "dinner", "snack"].map {
            try #require(note.range(of: $0)?.lowerBound)
        }
        #expect(positions == positions.sorted())
        #expect(note.hasPrefix("Still to answer: breakfast"))
    }
}
