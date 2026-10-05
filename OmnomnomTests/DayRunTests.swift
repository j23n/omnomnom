import Foundation
import Testing
@testable import Omnomnom

/// The run, and the three rules that keep it from punishing a normal week.
struct DayRunTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// October 2026 starts on a Thursday, so the cadence's Mondays, Wednesdays and
    /// Saturdays are the 3rd, 5th, 7th, 10th, 12th and 14th.
    private func october(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))
            ?? .distantPast
    }

    private func days(_ range: ClosedRange<Int>) -> [Date] {
        range.map { october($0) }
    }

    private func states(_ pairs: KeyValuePairs<Int, DayState>) -> [Date: DayState] {
        Dictionary(uniqueKeysWithValues: pairs.map { (october($0.key), $0.value) })
    }

    private func run(
        _ days: [Date], _ states: [Date: DayState], _ cadence: SamplingCadence = .everyDay, now: Int
    ) -> DayRun {
        DayRun.over(
            days: days,
            states: states,
            cadence: cadence,
            now: october(now, hour: 12),
            calendar: calendar
        )
    }

    // MARK: - Today is never a loss

    @Test func todayBeingUnansweredDoesNotBreakTheRun() {
        // Four answered days and a day that is simply not over yet.
        let result = run(
            days(1...5),
            states([1: .complete, 2: .complete, 3: .complete, 4: .complete, 5: .partial]),
            now: 5
        )
        #expect(result.current == 4)
        #expect(result.best == 4)
        #expect(result.open == nil)
    }

    @Test func yesterdayIsStillOpenRatherThanMissed() {
        let result = run(
            days(1...5),
            states([1: .complete, 2: .complete, 3: .complete, 4: .empty, 5: .empty]),
            now: 5
        )
        #expect(result.current == 3)
        #expect(result.open == october(4))
    }

    @Test func aDayOutsideTheGraceWindowIsAMiss() {
        let result = run(
            days(1...5),
            states([1: .complete, 2: .complete, 3: .empty, 4: .complete, 5: .complete]),
            now: 5
        )
        #expect(result.current == 2)
        #expect(result.best == 2)
        #expect(result.open == nil)
    }

    // MARK: - A gap never touches the best

    @Test func aGapEndsTheCurrentRunAndLeavesTheBestAlone() {
        let result = run(
            days(1...10),
            states([
                1: .complete, 2: .complete, 3: .complete, 4: .complete, 5: .complete,
                6: .empty,
                7: .complete, 8: .complete, 9: .complete, 10: .partial,
            ]),
            now: 10
        )
        #expect(result.current == 3)
        #expect(result.best == 5)
    }

    @Test func theBestIsNeverLessThanTheRunInHand() {
        let result = run(days(1...3), states([1: .complete, 2: .complete, 3: .complete]), now: 3)
        #expect(result.current == 3)
        #expect(result.best == 3)
    }

    // MARK: - What counts as answered

    @Test func aDayAcceptedFromYourUsualOneHoldsTheRun() {
        // Assumed is not evidence and is left out of every mean, but it is an answer.
        let result = run(days(1...3), states([1: .assumed, 2: .complete, 3: .assumed]), now: 3)
        #expect(result.current == 3)
    }

    @Test func aPartialDayIsNotAnAnswer() {
        // Entries exist and the user never said that was all of it, so yesterday is open
        // and the run in hand is only today.
        let result = run(days(1...3), states([1: .complete, 2: .partial, 3: .complete]), now: 3)
        #expect(result.current == 1)
        #expect(result.open == october(2))
    }

    @Test func aDayTheStoreHasNeverHeardOfIsEmpty() {
        let result = run(days(1...5), states([4: .complete, 5: .complete]), now: 5)
        #expect(result.current == 2)
    }

    // MARK: - The cadence steps over days rather than failing them

    @Test func daysTheCadenceDoesNotAskAboutAreNotMisses() {
        // Six asked days answered; every Tuesday and Thursday between them holds nothing.
        let result = run(
            days(1...14),
            states([3: .complete, 5: .complete, 7: .complete, 10: .complete, 12: .complete, 14: .complete]),
            .threeDaysAWeek,
            now: 14
        )
        #expect(result.current == 6)
        #expect(result.best == 6)
        #expect(result.open == nil)
    }

    @Test func aWindowWithNoAskedDaysCountsNothing() {
        // One week a month asks about the 1st to the 7th and stays quiet afterwards.
        let result = run(days(10...14), states([10: .complete, 12: .complete]), .oneWeekAMonth, now: 14)
        #expect(result == .empty)
    }

    // MARK: - The window

    @Test func daysThatHaveNotHappenedAreIgnored() {
        // A window reaching into the future must not read as a run of missed days.
        let result = run(days(1...10), states([1: .complete, 2: .complete, 3: .complete]), now: 3)
        #expect(result.current == 3)
        #expect(result.best == 3)
    }

    @Test func noDaysAtAllCountsNothing() {
        #expect(run([], [:], now: 5) == .empty)
    }
}
