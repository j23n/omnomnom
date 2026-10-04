import Foundation

/// Breakfast, lunch, dinner or snack. Stored on the entry and mirrored into
/// custom metadata on the HealthKit correlation.
nonisolated enum MealSlot: String, CaseIterable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// The SF Symbol shown next to the slot's name on Today.
    var symbolName: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// When this meal usually happens, for the slot the model names rather than the clock.
    ///
    /// The inverse of `inferred`, and the middle of each of its ranges. A snack has none
    /// on purpose: it is what the clock says when no other slot fits, so it has no hour of
    /// its own to move an entry to.
    var typicalTime: (hour: Int, minute: Int)? {
        switch self {
        case .breakfast: (8, 0)
        case .lunch: (12, 30)
        case .dinner: (19, 0)
        case .snack: nil
        }
    }

    /// The moment to record for this meal on `day`.
    ///
    /// Describing breakfast at nine in the evening should log breakfast, so the hour
    /// follows the meal rather than the clock — otherwise the label and the timestamp
    /// disagree and every other app reading Health sees an evening meal called breakfast.
    ///
    /// Never later than `now`, which is the one rule that matters: saying "dinner" over
    /// morning coffee would otherwise write seven in the evening, a meal that has not
    /// happened yet. A snack keeps the wall-clock time on the chosen day, as the Quantity
    /// sheet does, because it has no hour of its own.
    func timestamp(on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: now)
        let time = typicalTime ?? (hour: clock.hour ?? 12, minute: clock.minute ?? 0)
        guard let candidate = calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: day
        ) else { return min(day, now) }
        return min(candidate, now)
    }

    /// Guesses the slot from the hour of `date`. Editable by the user afterwards.
    static func inferred(from date: Date, calendar: Calendar = .current) -> MealSlot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}
