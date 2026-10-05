import Foundation
import Testing
@testable import Omnomnom

/// Which meals have an answer, where "nothing" is one.
struct DayAnswersTests {
    @Test func aLoggedMealIsAnswered() {
        let answers = DayAnswers(logged: [.breakfast, .lunch])
        #expect(answers.isAnswered(.breakfast))
        #expect(answers.isAnswered(.lunch))
        #expect(!answers.isAnswered(.dinner))
    }

    @Test func nothingTonightAnswersDinnerWithoutAnEntry() {
        // The whole reason a skipped slot is stored: without it the ring could never
        // close on a day someone genuinely did not eat dinner.
        let answers = DayAnswers(logged: [.breakfast, .lunch], skipped: [.dinner, .snack])
        #expect(answers.isAnswered(.dinner))
        #expect(answers.isAnswered)
        #expect(answers.unanswered.isEmpty)
    }

    @Test func theSlotsStillOwedAnAnswerKeepTheirOrder() {
        let answers = DayAnswers(logged: [.breakfast])
        #expect(answers.unanswered == [.lunch, .dinner, .snack])
    }

    @Test func aDayIsNotAnsweredUntilAllFourAre() {
        let answers = DayAnswers(logged: [.breakfast, .lunch, .dinner])
        #expect(!answers.isAnswered)
        #expect(answers.unanswered == [.snack])
    }

    @Test func aMealBothLoggedAndSkippedIsCountedOnce() {
        // Reachable: log a snack, then say the day held none. The answer stands either way.
        let answers = DayAnswers(logged: [.snack], skipped: [.snack])
        #expect(answers.answered == [.snack])
        #expect(answers.unanswered == [.breakfast, .lunch, .dinner])
    }

    @Test func entrySlotsAreDeduplicated() {
        // Four foods at breakfast is one answered meal.
        let answers = DayAnswers(entrySlots: [.breakfast, .breakfast, .breakfast, .lunch])
        #expect(answers.logged == [.breakfast, .lunch])
    }

    @Test func nothingAnsweredIsEmpty() {
        #expect(DayAnswers.empty.answered.isEmpty)
        #expect(DayAnswers.empty.unanswered == MealSlot.allCases)
        #expect(!DayAnswers.empty.isAnswered)
    }
}
