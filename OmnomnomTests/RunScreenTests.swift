import Foundation
import Testing
@testable import Omnomnom

/// The run screen's own words, and the month it draws.
struct RunScreenTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    // MARK: - The row on Shape

    @Test func theRowCountsDaysAndNamesTheBest() {
        #expect(RunSummaryRow.detail(DayRun(current: 17, best: 34, open: nil)) == "17 days answered · best 34")
    }

    @Test func oneDayAgreesWithItsNoun() {
        #expect(RunSummaryRow.detail(DayRun(current: 1, best: 1, open: nil)) == "1 day answered · best 1")
    }

    @Test func nothingAnsweredIsSaidPlainlyRatherThanAsAZero() {
        // "0 days answered · best 0" reads as a failure. Nobody has failed anything.
        #expect(RunSummaryRow.detail(.empty) == "No days answered yet")
    }

    @Test func aBrokenRunStillShowsTheBest() {
        // The whole point of keeping `best` out of the current run's reach.
        #expect(RunSummaryRow.detail(DayRun(current: 0, best: 34, open: nil)) == "0 days answered · best 34")
    }

    // MARK: - The month under it

    @Test func theMonthRunsFromItsFirstDayToToday() {
        let days = RunModel.monthToDate(endingAt: day(2026, 10, 5), calendar: calendar)
        #expect(days.count == 5)
        #expect(days.first == day(2026, 10, 1))
        #expect(days.last == day(2026, 10, 5))
    }

    @Test func nothingAfterTodayIsDrawn() {
        // A square for a day that has not happened looks exactly like a day someone
        // missed, which is the one thing this grid must not say.
        let days = RunModel.monthToDate(endingAt: day(2026, 10, 1), calendar: calendar)
        #expect(days == [day(2026, 10, 1)])
    }

    @Test func theFirstOfTheMonthIsAMonthOfOneDay() {
        let days = RunModel.monthToDate(endingAt: day(2026, 2, 1), calendar: calendar)
        #expect(days.count == 1)
    }

    @Test func aWholeMonthIsAWholeMonth() {
        let days = RunModel.monthToDate(endingAt: day(2026, 2, 28), calendar: calendar)
        #expect(days.count == 28)
    }

    // MARK: - What a cell says aloud

    @Test func aCellReadsItsDateThenTheMark() {
        let cell = RunDay(
            day: day(2026, 10, 5),
            answers: DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]),
            composition: .empty,
            state: .partial,
            isAsked: true
        )
        let spoken = RunView.label(for: cell)
        #expect(spoken.contains("3 of 4 meals answered."))
        #expect(!spoken.contains("Not a day you are asked about"))
    }

    @Test func aDayTheCadenceSkipsSaysSoRatherThanLookingLikeAMiss() {
        let cell = RunDay(
            day: day(2026, 10, 6),
            answers: .empty,
            composition: .empty,
            state: .empty,
            isAsked: false
        )
        let spoken = RunView.label(for: cell)
        #expect(spoken.contains("No meals answered yet."))
        #expect(spoken.hasSuffix("Not a day you are asked about."))
    }

    @Test func theGridNamesTheMonthItIsShowing() {
        let cell = RunDay(
            day: day(2026, 10, 5), answers: .empty, composition: .empty, state: .empty, isAsked: true
        )
        #expect(RunView.monthTitle([cell]).hasSuffix(", meal by meal"))
    }

    @Test func anEmptyGridStillHasAHeading() {
        #expect(RunView.monthTitle([]) == "This month, meal by meal")
    }
}
