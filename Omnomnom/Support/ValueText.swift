import DeveloperToolsSupport
import SwiftUI

/// A number with monospaced digits, so figures line up in columns and a caption does
/// not jitter as its value changes. An amount with a unit keeps the unit in the same
/// run of text and tells VoiceOver the unit's name: "75.4 grams", or "not recorded".
struct ValueText: View {
    private let text: String
    private let spoken: String

    /// A nutrient amount as `Formatters.amount` prints it; "–" when the value is unknown.
    init(_ value: Double?, unit: NutrientUnit) {
        text = Formatters.amount(value, unit: unit)
        spoken = Formatters.spokenAmount(value, unit: unit)
    }

    /// Text formatted elsewhere, such as "350 g · 08:10", read as written.
    init(_ text: String) {
        self.text = text
        spoken = text
    }

    var body: some View {
        Text(text)
            .monospacedDigit()
            .accessibilityLabel(spoken)
    }
}

#if DEBUG
#Preview("Amounts", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 8) {
        ValueText(1_648, unit: .kilocalorie)
            .font(.title.weight(.semibold))
        ValueText(92.4, unit: .gram)
        ValueText(2_130, unit: .milligram)
        ValueText(nil, unit: .gram)
        ValueText("1.5 servings · 351 g · 19:15")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
#endif
