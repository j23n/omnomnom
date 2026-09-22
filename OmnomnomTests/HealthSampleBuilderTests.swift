import Foundation
import Testing
@testable import Omnomnom

struct HealthSampleBuilderTests {
    private let entryID = UUID()
    private let all = Set(Nutrient.allCases)

    private func request(_ nutrition: Nutrition, version: Int = 1) -> HealthWriteRequest {
        HealthWriteRequest(
            entryID: entryID,
            foodName: "Apples, raw, with skin",
            mealSlot: .breakfast,
            start: Date(timeIntervalSince1970: 1_000_000),
            nutrition: nutrition,
            syncVersion: version
        )
    }

    @Test func fullAuthorizationYieldsEightSamplesInNutrientOrder() {
        let specs = HealthSampleBuilder.samples(for: request(.zero), authorized: all)
        #expect(specs.count == 8)
        #expect(specs.map(\.nutrient) == Nutrient.allCases)
        #expect(specs.map(\.unit) == Nutrient.allCases.map(\.unit))
    }

    @Test func syncIdentifiersFollowTheScheme() {
        let specs = HealthSampleBuilder.samples(for: request(.zero, version: 3), authorized: all)
        #expect(specs.first?.syncIdentifier == "\(entryID.uuidString).energy")
        #expect(specs.last?.syncIdentifier == "\(entryID.uuidString).sodium")
        #expect(specs.allSatisfy { $0.syncVersion == 3 })
        let correlation = HealthSampleBuilder.correlation(for: request(.zero, version: 3), authorized: all)
        #expect(correlation?.syncIdentifier == "\(entryID.uuidString).meal")
        #expect(correlation?.syncVersion == 3)
    }

    @Test func missingNutrientsAreSkipped() {
        let nutrition = Nutrition(energy: 89, protein: 1.09)
        let specs = HealthSampleBuilder.samples(for: request(nutrition), authorized: all)
        #expect(specs.map(\.nutrient) == [.energy, .protein])
        #expect(specs.map(\.value) == [89, 1.09])
    }

    @Test func unauthorizedNutrientsAreSkipped() {
        let specs = HealthSampleBuilder.samples(for: request(.zero), authorized: [.protein, .sodium])
        #expect(specs.map(\.nutrient) == [.protein, .sodium])
    }

    @Test func correlationCarriesFoodTypeMealSlotAndSamples() {
        let correlation = HealthSampleBuilder.correlation(for: request(.zero), authorized: [.energy])
        #expect(correlation?.foodType == "Apples, raw, with skin")
        #expect(correlation?.mealSlot == .breakfast)
        #expect(correlation?.samples.count == 1)
        #expect(correlation?.start == Date(timeIntervalSince1970: 1_000_000))
        #expect(HealthSampleBuilder.mealSlotMetadataKey == "com.j23n.omnomnom.mealSlot")
    }

    @Test func syncIdentifiersCoverWrittenNutrientsAndTheCorrelation() {
        let ids = HealthSampleBuilder.syncIdentifiers(entryID: entryID, nutrients: [.sodium, .energy])
        #expect(ids == [
            "\(entryID.uuidString).energy",
            "\(entryID.uuidString).sodium",
            "\(entryID.uuidString).meal",
        ])
        #expect(HealthSampleBuilder.syncIdentifiers(entryID: entryID, nutrients: []).isEmpty)
        #expect(HealthSampleBuilder.syncIdentifiers(entryID: entryID, nutrients: all).count == 9)
    }

    @Test func noAuthorizedSampleMeansNoCorrelation() {
        #expect(HealthSampleBuilder.correlation(for: request(.zero), authorized: []) == nil)
        let onlyMissing = Nutrition(energy: nil, fiber: 2)
        #expect(HealthSampleBuilder.correlation(for: request(onlyMissing), authorized: [.energy]) == nil)
    }
}
