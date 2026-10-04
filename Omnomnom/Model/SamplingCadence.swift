import Foundation

/// How often the app asks for a complete day.
///
/// The overview does not need every day. Three complete days a week, or one complete week
/// a month, is enough to read a trend over months, and it is how dietary intake is
/// measured whenever a weighed record is not affordable.
///
/// **It changes what the app asks for and never what it computes over.** A complete day
/// outside the cadence is still a complete day and still counts toward every mean —
/// discarding real data because a schedule did not ask for it would be absurd. What the
/// cadence decides is whether Today prompts: on a day it did not ask about, the app is
/// quiet.
///
/// Membership is derived from the date rather than stored, so the same day is always in
/// or out and there is no state to drift.
nonisolated enum SamplingCadence: String, Hashable, Sendable, CaseIterable, Identifiable {
    case everyDay
    case threeDaysAWeek
    case oneWeekAMonth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDay: "Every day"
        case .threeDaysAWeek: "Three days a week"
        case .oneWeekAMonth: "One week a month"
        }
    }

    /// What the setting tells the user it will do.
    var explanation: String {
        switch self {
        case .everyDay:
            "Today asks about every day."
        case .threeDaysAWeek:
            "Today asks on Mondays, Wednesdays and Saturdays, so a weekend is in the picture."
        case .oneWeekAMonth:
            "Today asks during the first week of each month and stays quiet after it."
        }
    }

    /// Weekdays the three-day cadence asks about.
    ///
    /// Monday, Wednesday and Saturday rather than three weekdays: what someone eats at a
    /// weekend is often the part that differs most, and a sample that never sees one
    /// describes their working week instead of their diet.
    static let sampledWeekdays: Set<Int> = [2, 4, 7]

    /// Days of the month the weekly cadence asks about.
    static let sampledDaysOfMonth = 1...7

    /// Whether the app should ask about this day.
    func asks(about day: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .everyDay:
            true
        case .threeDaysAWeek:
            Self.sampledWeekdays.contains(calendar.component(.weekday, from: day))
        case .oneWeekAMonth:
            Self.sampledDaysOfMonth.contains(calendar.component(.day, from: day))
        }
    }

    /// The Settings key the cadence is stored under.
    static let key = "samplingCadence"

    /// What is stored when nothing has been chosen.
    static let standard = SamplingCadence.everyDay
}
