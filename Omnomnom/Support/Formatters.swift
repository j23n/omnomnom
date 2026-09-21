import Foundation

/// Display formatting for nutrient amounts and gram inputs. Numbers only, never verdicts.
nonisolated enum Formatters {
    /// "123 kcal", "12.3 g", "455 mg"; "–" when the value is unknown.
    static func amount(_ value: Double?, unit: NutrientUnit) -> String {
        guard let value else { return "–" }
        return "\(number(value, unit: unit)) \(unit.symbol)"
    }

    /// The number alone, with the precision that suits the unit.
    static func number(_ value: Double, unit: NutrientUnit) -> String {
        switch unit {
        case .kilocalorie, .milligram:
            value.formatted(.number.precision(.fractionLength(0)))
        case .gram:
            value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    /// "182 g" or "62.5 g" for portion chips and entry rows.
    static func grams(_ value: Double) -> String {
        "\(number(value, unit: .gram)) g"
    }

    /// Smallest and largest amount the gram field accepts, in grams.
    static let minimumGrams = 0.1
    static let maximumGrams = 5000.0

    /// "0.1 and 5000 g", for the inline hint under the gram field.
    static var gramsRangeText: String {
        let lower = minimumGrams.formatted(.number.precision(.fractionLength(0...1)))
        let upper = maximumGrams.formatted(.number.precision(.fractionLength(0)).grouping(.never))
        return "\(lower) and \(upper) g"
    }

    /// Parses user-typed grams, accepting a comma as decimal separator.
    /// `nil` when the text is not a number or lies outside `minimumGrams...maximumGrams`.
    static func parseGrams(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        guard value >= minimumGrams, value <= maximumGrams else { return nil }
        return value
    }

    /// Text for the gram field from a stored value; drops a trailing ".0".
    static func gramsFieldText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// "Today", "Yesterday", "Tomorrow" or a medium date.
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
