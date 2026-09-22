import Foundation

/// Display formatting for nutrient amounts and the parsing of typed amounts. Numbers only, never verdicts.
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

    /// "182 g" or "62.5 g" for portion chips and amount fields.
    static func grams(_ value: Double) -> String {
        "\(number(value, unit: .gram)) g"
    }

    /// "350 g": whole grams for entry captions, where a decimal adds nothing.
    static func wholeGrams(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) g"
    }

    /// The amount as VoiceOver should read it: "75.4 grams", "455 milligrams";
    /// "not recorded" when the value is unknown.
    static func spokenAmount(_ value: Double?, unit: NutrientUnit) -> String {
        guard let value else { return "not recorded" }
        return "\(number(value, unit: unit)) \(unit.spokenName)"
    }

    /// "1 serving", "1.5 servings", "0.5 servings".
    static func servings(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return value == 1 ? "1 serving" : "\(number) servings"
    }

    /// Smallest and largest amount the gram field accepts, in grams.
    static let minimumGrams = 0.1
    static let maximumGrams = 5000.0

    /// Smallest and largest number of servings the field accepts when logging a recipe.
    static let minimumServings = 0.1
    static let maximumServings = 50.0

    /// Largest per-100 g value a custom food field accepts; sodium in milligrams sets the scale.
    static let maximumNutrientValue = 100_000.0

    /// "0.1 and 5000 g", for the inline hint under the gram field.
    static var gramsRangeText: String {
        "\(rangeText(minimumGrams, maximumGrams)) g"
    }

    /// "0.1 and 50 servings", for the inline hint under the servings field.
    static var servingsRangeText: String {
        "\(rangeText(minimumServings, maximumServings)) servings"
    }

    /// Parses user-typed grams, accepting a comma as decimal separator.
    /// `nil` when the text is not a number or lies outside `minimumGrams...maximumGrams`.
    static func parseGrams(_ text: String) -> Double? {
        parse(text, in: minimumGrams...maximumGrams)
    }

    /// Parses a typed servings count the same way, within `minimumServings...maximumServings`.
    static func parseServings(_ text: String) -> Double? {
        parse(text, in: minimumServings...maximumServings)
    }

    /// Parses a per-100 g value typed for a custom food: 0 or more, up to `maximumNutrientValue`.
    static func parseNutrientValue(_ text: String) -> Double? {
        parse(text, in: 0...maximumNutrientValue)
    }

    /// Text for an amount field from a stored value; drops a trailing ".0".
    static func fieldText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Text to prefill the amount field with: at most one decimal, so a stored
    /// 350.625 g reads "350.6" and a whole amount stays whole.
    static func prefillText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// "Today", "Yesterday", "Tomorrow" or a short weekday and date, "Mon 21 Sep", in
    /// the order the locale puts them.
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// The full date under `dayTitle`: "Monday, 21 September 2026".
    static func daySubtitle(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar))
    }

    private static func parse(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func rangeText(_ lower: Double, _ upper: Double) -> String {
        let lowerText = lower.formatted(.number.precision(.fractionLength(0...1)))
        let upperText = upper.formatted(.number.precision(.fractionLength(0)).grouping(.never))
        return "\(lowerText) and \(upperText)"
    }
}
