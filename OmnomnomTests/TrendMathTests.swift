import Foundation
import Testing
@testable import Omnomnom

/// The two rules that decide whether the Trends screen is honest: the mean breaks over a
/// gap, and it never appears without saying what it rests on.
struct TrendMathTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
            .addingTimeInterval(Double(offset) * 86_400)
    }

    private func days(_ count: Int) -> [Date] {
        (0..<count).map(day)
    }

    // MARK: - The break rule

    @Test func noMeanUntilEnoughDaysHoldSomething() {
        let range = days(5)
        let values = Dictionary(uniqueKeysWithValues: range.map { ($0, 2_000.0) })
        let series = TrendMath.series(days: range, values: values, states: [:])
        // Four is the minimum, so the first three days carry no mean at all.
        #expect(series.prefix(3).allSatisfy { $0.mean == nil })
        #expect(series[3].mean == 2_000)
        #expect(series[4].mean == 2_000)
    }

    @Test func theMeanBreaksOverAGapRatherThanBridgingIt() {
        // A line drawn across four blank days would be the app asserting figures nobody
        // recorded, which is the failure coverage exists to prevent.
        let range = days(14)
        var values: [Date: Double] = [:]
        for index in 0...6 { values[day(index)] = 2_000 }
        for index in 11...13 { values[day(index)] = 2_000 }
        let series = TrendMath.series(days: range, values: values, states: [:])
        #expect(series[6].mean != nil)
        #expect(series[10].mean == nil)
        #expect(series[13].mean == nil)
    }

    @Test func aGapDayCarriesNoValueRatherThanAZero() {
        let range = days(3)
        let series = TrendMath.series(days: range, values: [day(0): 2_000], states: [:])
        #expect(series[0].value == 2_000)
        #expect(series[1].value == nil)
        #expect(series[2].value == nil)
    }

    @Test func theMeanAveragesOnlyTheDaysThatHoldSomething() {
        let range = days(7)
        let values: [Date: Double] = [
            day(0): 1_000, day(1): 2_000, day(2): 3_000, day(6): 4_000,
        ]
        // Four present days in the window: (1000+2000+3000+4000)/4.
        #expect(TrendMath.mean(endingAt: 6, days: range, values: values) == 2_500)
    }

    @Test func theWindowIsTrailingAndSevenLong() {
        let range = days(10)
        let values = Dictionary(uniqueKeysWithValues: range.map { ($0, 0.0) }).merging(
            [day(0): 7_000], uniquingKeysWith: { _, new in new }
        )
        // Day 7's window is days 1 to 7, so the outlier on day 0 has left it.
        #expect(TrendMath.mean(endingAt: 6, days: range, values: values) == 1_000)
        #expect(TrendMath.mean(endingAt: 7, days: range, values: values) == 0)
    }

    // MARK: - The basis

    @Test func everyStateIsCounted() {
        let range = days(4)
        let states: [Date: DayState] = [
            day(0): .complete, day(1): .partial, day(2): .assumed, day(3): .empty,
        ]
        let basis = TrendMath.basis(days: range, states: states, values: [:])
        #expect(basis.complete == 1)
        #expect(basis.partial == 1)
        #expect(basis.assumed == 1)
        #expect(basis.empty == 1)
        #expect(basis.total == 4)
    }

    @Test func theSentenceNamesCountsAndNeverAShare() {
        let basis = TrendBasis(complete: 67, partial: 7, assumed: 7, empty: 9)
        #expect(basis.sentence == "Means cover 67 complete days, 7 partial, 7 assumed and 9 with nothing logged.")
        #expect(!basis.sentence.contains("%"))
        #expect(!basis.sentence.contains("/"))
    }

    @Test func oneCompleteDayIsSingular() {
        #expect(TrendBasis(complete: 1).sentence == "Means cover 1 complete day.")
    }

    @Test func assumedDaysAreAlwaysNamedWhenThereAreAny() {
        // A day accepted in one tap is in the figures, so the user is told how much of
        // the line is theirs.
        let basis = TrendBasis(complete: 10, assumed: 3)
        #expect(basis.sentence.contains("3 assumed"))
    }

    @Test func withNoCompleteDaysTheSentenceSaysSoWithoutCountingZero() {
        let basis = TrendBasis(complete: 0, partial: 3, assumed: 0, empty: 2)
        #expect(basis.sentence == "No complete days yet: 3 partial and 2 with nothing logged.")
        #expect(!basis.hasMean)
    }

    @Test func anEmptyRangeSaysNothingRatherThanZero() {
        #expect(TrendBasis().sentence == "Nothing logged in this range.")
        #expect(!TrendBasis().hasMean)
    }

    // MARK: - The stated mean

    @Test func theStatedMeanUsesCompleteDaysOnly() {
        // A day holding breakfast alone would drag a mean down while looking like a light
        // day, which is the one way the overview could mislead in the direction that
        // matters.
        let range = days(3)
        let values: [Date: Double] = [day(0): 2_000, day(1): 500, day(2): 2_200]
        let states: [Date: DayState] = [day(0): .complete, day(1): .partial, day(2): .complete]
        #expect(TrendMath.completeDayMean(days: range, values: values, states: states) == 2_100)
    }

    @Test func noCompleteDaysMeansNoStatedMean() {
        let range = days(2)
        let values: [Date: Double] = [day(0): 2_000, day(1): 2_000]
        let states: [Date: DayState] = [day(0): .partial, day(1): .assumed]
        #expect(TrendMath.completeDayMean(days: range, values: values, states: states) == nil)
    }

    // MARK: - The range

    @Test func everyDayInTheRangeIsPresentIncludingGaps() {
        let range = TrendMath.days(from: day(0), to: day(6), calendar: calendar)
        #expect(range.count == 7)
        #expect(range.first == day(0))
        #expect(range.last == day(6))
    }

    @Test func aSingleDayRangeIsOneDay() {
        #expect(TrendMath.days(from: day(3), to: day(3), calendar: calendar).count == 1)
    }

    @Test func aBackwardsRangeIsEmptyRatherThanInfinite() {
        #expect(TrendMath.days(from: day(5), to: day(1), calendar: calendar).isEmpty)
    }
}

/// Splitting a series into the runs a chart draws as separate lines.
struct TrendSegmentTests {
    private func point(_ offset: Int, mean: Double?) -> TrendPoint {
        TrendPoint(
            day: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400),
            value: mean, mean: mean, state: mean == nil ? .empty : .complete
        )
    }

    @Test func anUnbrokenSeriesIsOneRun() {
        let points = (0..<5).map { point($0, mean: 2_000) }
        #expect(TrendMath.segments(points).count == 1)
        #expect(TrendMath.segments(points).first?.count == 5)
    }

    @Test func aGapSplitsTheRunSoNoLineCrossesIt() {
        let points = [
            point(0, mean: 2_000), point(1, mean: 2_000),
            point(2, mean: nil), point(3, mean: nil),
            point(4, mean: 2_100), point(5, mean: 2_100),
        ]
        let runs = TrendMath.segments(points)
        #expect(runs.count == 2)
        #expect(runs[0].count == 2)
        #expect(runs[1].count == 2)
    }

    @Test func leadingAndTrailingGapsProduceNoEmptyRuns() {
        let points = [
            point(0, mean: nil), point(1, mean: 2_000), point(2, mean: nil),
        ]
        let runs = TrendMath.segments(points)
        #expect(runs.count == 1)
        #expect(runs.first?.count == 1)
    }

    @Test func aSeriesWithNoMeanAtAllHasNoRuns() {
        let points = (0..<4).map { point($0, mean: nil) }
        #expect(TrendMath.segments(points).isEmpty)
    }

    @Test func anEmptySeriesHasNoRuns() {
        #expect(TrendMath.segments([]).isEmpty)
    }
}
