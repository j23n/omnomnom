import Foundation
import Testing
@testable import Omnomnom

/// The queue: what is in it, in what order, and the days it says nothing about.
struct LooseEndTests {
    private func row(
        _ name: String, guessed: Bool = false, wording: String? = nil,
        missing: Set<Nutrient> = []
    ) -> LoggedRow {
        LoggedRow(
            entryID: UUID(), foodName: name, wording: wording, guessed: guessed, missing: missing
        )
    }

    private func items(
        rows: [LoggedRow] = [],
        answers: DayAnswers = DayAnswers(logged: Set(MealSlot.allCases)),
        usual: [MealSlot: String] = [:],
        isAsked: Bool = true,
        isClosed: Bool = true
    ) -> [LooseEnd] {
        LooseEnd.items(
            rows: rows, answers: answers, usual: usual, isAsked: isAsked, isClosed: isClosed
        )
    }

    // MARK: - When it says nothing

    @Test func anAnsweredAndClosedDayHasNothingLoose() {
        #expect(items().isEmpty)
    }

    @Test func aDayTheCadenceDoesNotAskAboutRaisesNothing() {
        // The cadence decides when the app speaks, and this screen is the app speaking.
        // A Tuesday outside the sample is not a day anyone failed to answer.
        let queue = items(
            rows: [row("Feta", missing: [.fiber])],
            answers: DayAnswers(logged: [.breakfast]),
            isAsked: false,
            isClosed: false
        )
        #expect(queue.isEmpty)
    }

    // MARK: - Unanswered meals

    @Test func everyUnansweredMealIsACardInTheOrderTheyAreEaten() {
        let queue = items(answers: DayAnswers(logged: [.lunch], skipped: [.snack]), isClosed: false)
        #expect(queue.map(\.kind) == [.unansweredMeal(.breakfast), .unansweredMeal(.dinner)])
    }

    @Test func aMealWithAUsualLineOffersIt() {
        let queue = items(
            answers: DayAnswers(logged: [.breakfast, .lunch, .snack]),
            usual: [.dinner: "pasta with tomato sauce"],
            isClosed: false
        )
        #expect(queue.first?.title == "Dinner is unanswered")
        #expect(queue.first?.detail == "You usually have pasta with tomato sauce.")
    }

    @Test func aMealWithNoUsualLineSaysWhatCanBeDoneInstead() {
        let queue = items(answers: DayAnswers(logged: [.breakfast, .lunch, .snack]), isClosed: false)
        #expect(queue.first?.detail == "Say what you had, or say there was nothing.")
    }

    @Test func aSkippedMealIsAnsweredAndRaisesNothing() {
        let queue = items(answers: DayAnswers(logged: [], skipped: Set(MealSlot.allCases)))
        #expect(queue.isEmpty)
    }

    // MARK: - Marked rows

    @Test func aGuessedRowIsACardQuotingWhatWasSaid() {
        let queue = items(rows: [row("Greek salad", guessed: true, wording: "a side salad")])
        #expect(queue.count == 1)
        #expect(queue[0].kind == .guessedMatch)
        #expect(queue[0].title == "Greek salad")
        #expect(queue[0].detail == "From “a side salad”")
    }

    @Test func aGuessedRowWithNoWordsBehindItStillSaysWhoChose() {
        let queue = items(rows: [row("Oat flakes", guessed: true)])
        #expect(queue[0].detail == "Matched for you")
    }

    @Test func aSettledRowIsNotALooseEnd() {
        #expect(items(rows: [row("Oat flakes")]).isEmpty)
    }

    @Test func eachGuessedRowGetsItsOwnCard() {
        let queue = items(rows: [
            row("Greek salad", guessed: true), row("Rye bread", guessed: true), row("Banana")
        ])
        #expect(queue.count == 2)
        #expect(queue.allSatisfy { $0.kind == .guessedMatch })
        // Each about its own entry, or answering one would answer the other.
        #expect(Set(queue.compactMap(\.entryID)).count == 2)
    }

    // MARK: - Missing figures

    @Test func aMissingFigureIsOneCardPerNutrientAndNotOnePerRow() {
        // 666 of the 10,440 bundled rows are short of something, so a card per row would
        // bury everything else here on an ordinary day.
        let queue = items(rows: [
            row("Feta", missing: [.fiber]),
            row("Apple juice", missing: [.fiber])
        ])
        #expect(queue.count == 1)
        #expect(queue[0].kind == .missingFigure(.fiber))
        #expect(queue[0].title == "2 foods have no fiber figure")
    }

    @Test func oneRowShortOfAFigureNamesIt() {
        let queue = items(rows: [row("Feta", missing: [.fiber]), row("Banana")])
        #expect(queue[0].title == "One food has no fiber figure")
        #expect(queue[0].detail == "Feta. Today's fiber is a floor, not a total.")
    }

    @Test func acardAboutOneRowCarriesThatRow() {
        // What makes "pick a fuller row" possible: a single short row can be swapped,
        // where two of them is a question with no one answer.
        let single = row("Feta", missing: [.fiber])
        let queue = items(rows: [single])
        #expect(queue[0].entryID == single.entryID)
        let pair = items(rows: [single, row("Apple juice", missing: [.fiber])])
        #expect(pair[0].entryID == nil)
    }

    @Test func figuresAreNamedInTheirOwnDisplayOrder() {
        // Never in order of how many rows are short of them, which would be a judgement
        // about which gap matters.
        let queue = items(rows: [row("Feta", missing: [.sodium, .fiber, .energy])])
        #expect(queue.map(\.kind) == [
            .missingFigure(.energy), .missingFigure(.fiber), .missingFigure(.sodium)
        ])
    }

    // MARK: - The day itself

    @Test func anAnsweredDayThatIsNotClosedIsTheLastCard() {
        let queue = items(rows: [row("Greek salad", guessed: true)], isClosed: false)
        #expect(queue.count == 2)
        #expect(queue.last?.kind == .dayNotClosed)
    }

    @Test func aDayWithMealsStillOwedDoesNotOfferToCloseItself() {
        // Closing it would claim the day holds everything eaten, which is exactly what
        // the unanswered meals above say it does not.
        let queue = items(answers: DayAnswers(logged: [.breakfast]), isClosed: false)
        #expect(!queue.contains { $0.kind == .dayNotClosed })
    }

    // MARK: - What the heading says

    @Test func theHeadingCountsAndTheLineUnderItPromisesTheDay() {
        #expect(LooseEnd.heading(3) == "3 loose ends")
        #expect(LooseEnd.heading(1) == "1 loose end")
        #expect(LooseEnd.heading(0) == "Nothing loose")
        #expect(LooseEnd.subheading(3, day: "Tuesday") == "Clear these and Tuesday is answered")
        #expect(LooseEnd.subheading(0, day: "Tuesday") == "Tuesday is answered")
    }

    @Test func nothingInTheQueueIsAPercentage() {
        let queue = items(
            rows: [row("Greek salad", guessed: true, wording: "a side salad"), row("Feta", missing: [.fiber])],
            answers: DayAnswers(logged: [.breakfast]),
            usual: [.dinner: "pasta"],
            isClosed: false
        )
        #expect(!queue.isEmpty)
        for item in queue {
            #expect(!item.title.contains("%"))
            #expect(!item.detail.contains("%"))
            #expect(!item.title.contains("per cent"))
        }
        #expect(!LooseEnd.heading(queue.count).contains("%"))
    }

    @Test func theSecondAnswerToAMealIsInTheWordsOfThatMeal() {
        // "Nothing for dinner" is not a sentence anyone says.
        #expect(LooseEndsView.when(.breakfast) == "this morning")
        #expect(LooseEndsView.when(.dinner) == "tonight")
    }
}
