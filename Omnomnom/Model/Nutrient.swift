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
}
