import Foundation
import Testing
@testable import Omnomnom

/// How often the app asks about a day — and what that must not touch.
struct SamplingCadenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// 2026-10-05 was a Monday.
    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? .now
    }

    private func day(offsetFromMonday offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
    }

    @Test func everyDayAsksAboutEveryDay() {
        for offset in 0..<14 {
            #expect(SamplingCadence.everyDay.asks(about: day(offsetFromMonday: offset), calendar: calendar))
        }
    }

    @Test func threeDaysAWeekAsksOnMondayWednesdayAndSaturday() {
        let asked = (0..<7).filter {
            SamplingCadence.threeDaysAWeek.asks(about: day(offsetFromMonday: $0), calendar: calendar)
        }
        #expect(asked == [0, 2, 5])
    }

    @Test func theThreeDaySampleIncludesAWeekend() {
        // A sample that never sees a weekend describes someone's working week rather
        // than their diet, and the weekend is often the part that differs most.
        let saturday = day(offsetFromMonday: 5)
        #expect(calendar.component(.weekday, from: saturday) == 7)
        #expect(SamplingCadence.threeDaysAWeek.asks(about: saturday, calendar: calendar))
    }

    @Test func oneWeekAMonthAsksOnTheFirstSevenDays() {
        for dayOfMonth in 1...7 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: dayOfMonth)) ?? .now
            #expect(SamplingCadence.oneWeekAMonth.asks(about: date, calendar: calendar))
        }
        for dayOfMonth in [8, 15, 28, 31] {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: dayOfMonth)) ?? .now
            #expect(!SamplingCadence.oneWeekAMonth.asks(about: date, calendar: calendar))
        }
    }

    @Test func membershipIsDerivedSoTheSameDayIsAlwaysTheSame() {
        // Nothing is stored, so there is no state to drift and no migration to get wrong.
        let date = day(offsetFromMonday: 3)
        for cadence in SamplingCadence.allCases {
            let first = cadence.asks(about: date, calendar: calendar)
            #expect(cadence.asks(about: date, calendar: calendar) == first)
        }
    }

    @Test func everyCadenceExplainsItselfWithoutAFigure() {
        for cadence in SamplingCadence.allCases {
            #expect(!cadence.label.isEmpty)
            #expect(!cadence.explanation.isEmpty)
            #expect(!cadence.explanation.contains("%"))
        }
    }
}
