import Foundation

/// How far back the Trends screen looks.
///
/// No week. A seven-day mean cannot be drawn over seven days, so a week view would have
/// to fall back to bare daily columns, which makes one control mean two different things
/// and invites exactly the day-to-day reading this app is not for. A month is the
/// shortest range on which the thing being plotted exists.
nonisolated enum TrendRange: String, Hashable, Sendable, CaseIterable, Identifiable {
    case month
    case quarter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: "Month"
        case .quarter: "Quarter"
        }
    }

    var days: Int {
        switch self {
        case .month: 30
        case .quarter: 90
        }
    }

    /// The first day of the range, counting back from `end` inclusive.
    func start(endingAt end: Date, calendar: Calendar = .current) -> Date {
        let last = calendar.startOfDay(for: end)
        return calendar.date(byAdding: .day, value: -(days - 1), to: last) ?? last
    }
}
