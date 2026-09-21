import Foundation
import Testing
@testable import Omnomnom

struct NutritionTests {
    private let apple = Nutrition(
        energy: 52, protein: 0.26, carbohydrates: 13.8, fatTotal: 0.17,
        fatSaturated: 0.028, fiber: 2.4, sugar: 10.4, sodium: 1
    )

    @Test func scalingIsPer100g() {
        let scaled = apple.scaled(toGrams: 200)
        #expect(scaled.energy == 104)
        #expect(scaled.sodium == 2)
        #expect(scaled.carbohydrates.map { abs($0 - 27.6) < 0.0001 } == true)
    }

    @Test func scalingKeepsMissingNutrientsMissing() {
        let banana = Nutrition(energy: 89, protein: 1.09, fatSaturated: nil)
        let scaled = banana.scaled(toGrams: 50)
        #expect(scaled.fatSaturated == nil)
        #expect(scaled.energy == 44.5)
        #expect(scaled.presentNutrients == [.energy, .protein])
    }

    @Test func additionTreatsOneSidedNilAsZeroAndBothSidedNilAsNil() {
        let a = Nutrition(energy: 10, fiber: 1)
        let b = Nutrition(energy: 5, sugar: 2)
        let sum = a + b
        #expect(sum.energy == 15)
        #expect(sum.fiber == 1)
        #expect(sum.sugar == 2)
        #expect(sum.sodium == nil)
    }

    @Test func emptyIsIdentityAndZeroFillsBlanks() {
        #expect(apple + .empty == apple)
        let withZero = Nutrition(energy: 1) + .zero
        #expect(withZero.fiber == 0)
        #expect(withZero.energy == 1)
    }

    @Test func subscriptReadsAndWritesEveryNutrient() {
        var nutrition = Nutrition.empty
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            nutrition[nutrient] = Double(index)
        }
        for (index, nutrient) in Nutrient.allCases.enumerated() {
            #expect(nutrition[nutrient] == Double(index))
        }
    }

    @Test func codableRoundTripPreservesNils() throws {
        let original = Nutrition(energy: 89, protein: 1.09, fatSaturated: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Nutrition.self, from: data)
        #expect(decoded == original)
    }

    @Test func nutrientMetadata() {
        #expect(Nutrient.allCases.count == 8)
        #expect(Nutrient.primary == [.energy, .protein, .carbohydrates, .fatTotal])
        #expect(Nutrient.energy.unit == .kilocalorie)
        #expect(Nutrient.sodium.unit == .milligram)
        #expect(Nutrient.fiber.unit == .gram)
        #expect(Nutrient.energy.healthIdentifier == "HKQuantityTypeIdentifierDietaryEnergyConsumed")
        #expect(Nutrient.fatSaturated.healthIdentifier == "HKQuantityTypeIdentifierDietaryFatSaturated")
    }

    @Test func mealSlotInference() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func at(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour)) ?? Date.now
        }
        #expect(MealSlot.inferred(from: at(7), calendar: calendar) == .breakfast)
        #expect(MealSlot.inferred(from: at(12), calendar: calendar) == .lunch)
        #expect(MealSlot.inferred(from: at(19), calendar: calendar) == .dinner)
        #expect(MealSlot.inferred(from: at(16), calendar: calendar) == .snack)
        #expect(MealSlot.inferred(from: at(23), calendar: calendar) == .snack)
    }
}
