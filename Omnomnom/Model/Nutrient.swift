import Foundation

/// The eight nutrients this app records. Order is display order.
///
/// `healthIdentifier` is the raw value of the matching `HKQuantityTypeIdentifier`,
/// kept as a string so the model layer never imports HealthKit.
nonisolated enum Nutrient: String, CaseIterable, Codable, Sendable {
    case energy
    case protein
    case carbohydrates
    case fatTotal
    case fatSaturated
    case fiber
    case sugar
    case sodium

    /// Raw value of the `HKQuantityTypeIdentifier` for this nutrient.
    var healthIdentifier: String {
        switch self {
        case .energy: "HKQuantityTypeIdentifierDietaryEnergyConsumed"
        case .protein: "HKQuantityTypeIdentifierDietaryProtein"
        case .carbohydrates: "HKQuantityTypeIdentifierDietaryCarbohydrates"
        case .fatTotal: "HKQuantityTypeIdentifierDietaryFatTotal"
        case .fatSaturated: "HKQuantityTypeIdentifierDietaryFatSaturated"
        case .fiber: "HKQuantityTypeIdentifierDietaryFiber"
        case .sugar: "HKQuantityTypeIdentifierDietarySugar"
        case .sodium: "HKQuantityTypeIdentifierDietarySodium"
        }
    }

    /// The nutrient for a raw `HKQuantityTypeIdentifier`, or `nil` for a type this app does not record.
    init?(healthIdentifier: String) {
        guard let match = Nutrient.allCases.first(where: { $0.healthIdentifier == healthIdentifier }) else { return nil }
        self = match
    }

    var unit: NutrientUnit {
        switch self {
        case .energy: .kilocalorie
        case .sodium: .milligram
        default: .gram
        }
    }

    var displayName: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fatTotal: "Fat"
        case .fatSaturated: "Saturated fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .sodium: "Sodium"
        }
    }

    /// Short label for tight layouts such as the totals row.
    var shortName: String {
        switch self {
        case .carbohydrates: "Carbs"
        case .fatSaturated: "Sat. fat"
        default: displayName
        }
    }

    /// A fact about what the figure measures, shown wherever it is charted.
    ///
    /// Only sugar has one, and it matters: Ciqual and the BLS publish *total* sugars,
    /// which includes the fruit and the lactose nobody is usually asking about, and no
    /// permissively licensed composition table separates free or added sugar. So a day of
    /// fruit and yoghurt reads high on the line most people take to be about
    /// confectionery. The answer is not to hide the chart but to label it, on the screen
    /// rather than in a help page.
    ///
    /// This says what is measured, never how much to trust it. A chart that annotates
    /// which of someone's own figures to believe is a step from telling them what to do
    /// about it.
    var measurementCaveat: String? {
        switch self {
        case .sugar: "total sugars, including those naturally present"
        default: nil
        }
    }

    /// Energy, protein, carbohydrates and fat get primary weight on Today.
    var isPrimary: Bool {
        switch self {
        case .energy, .protein, .carbohydrates, .fatTotal: true
        default: false
        }
    }

    static var primary: [Nutrient] { allCases.filter(\.isPrimary) }
    static var secondary: [Nutrient] { allCases.filter { !$0.isPrimary } }
}

/// Unit a nutrient is stored and written in. Matches both the database and HealthKit.
nonisolated enum NutrientUnit: String, Codable, Sendable {
    case kilocalorie
    case gram
    case milligram

    var symbol: String {
        switch self {
        case .kilocalorie: "kcal"
        case .gram: "g"
        case .milligram: "mg"
        }
    }

    /// The unit's name for VoiceOver, which would otherwise spell out the symbol.
    var spokenName: String {
        switch self {
        case .kilocalorie: "kilocalories"
        case .gram: "grams"
        case .milligram: "milligrams"
        }
    }
}
