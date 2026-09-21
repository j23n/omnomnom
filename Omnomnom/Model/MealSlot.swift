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
