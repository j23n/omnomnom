import HealthKit
import Testing
@testable import Omnomnom

/// The model layer stores HealthKit identifiers as strings; this pins them to the SDK constants.
/// Imports HealthKit for the constants only and never touches a store.
struct NutrientIdentifierTests {
    private static let expected: [Nutrient: HKQuantityTypeIdentifier] = [
        .energy: .dietaryEnergyConsumed,
        .protein: .dietaryProtein,
        .carbohydrates: .dietaryCarbohydrates,
        .fatTotal: .dietaryFatTotal,
        .fatSaturated: .dietaryFatSaturated,
        .fiber: .dietaryFiber,
        .sugar: .dietarySugar,
        .sodium: .dietarySodium,
    ]

    @Test func everyNutrientMatchesItsHealthKitIdentifier() throws {
        #expect(Self.expected.count == Nutrient.allCases.count)
        for nutrient in Nutrient.allCases {
            let identifier = try #require(Self.expected[nutrient])
            #expect(nutrient.healthIdentifier == identifier.rawValue, "\(nutrient)")
        }
    }
}
