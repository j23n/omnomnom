import Foundation
import Testing
@testable import Omnomnom

struct SyncIdentifierTests {
    private let entryID = UUID()

    @Test func everyNutrientRoundTrips() throws {
        for nutrient in Nutrient.allCases {
            let id = SyncIdentifier.make(entryID: entryID, nutrient: nutrient)
            #expect(id == "\(entryID.uuidString).\(nutrient.rawValue)")
            let parsed = try #require(SyncIdentifier.parse(id))
            #expect(parsed.entryID == entryID)
            #expect(parsed.part == .nutrient(nutrient))
        }
    }

    @Test func mealRoundTrips() throws {
        let id = SyncIdentifier.make(mealFor: entryID)
        #expect(id == "\(entryID.uuidString).meal")
        let parsed = try #require(SyncIdentifier.parse(id))
        #expect(parsed.entryID == entryID)
        #expect(parsed.part == .meal)
    }

    @Test func builderUsesTheSameScheme() {
        let ids = HealthSampleBuilder.syncIdentifiers(entryID: entryID, nutrients: [.energy])
        #expect(ids == [SyncIdentifier.make(entryID: entryID, nutrient: .energy), SyncIdentifier.make(mealFor: entryID)])
    }

    @Test func garbageAndForeignIdentifiersDoNotParse() {
        #expect(SyncIdentifier.parse("") == nil)
        #expect(SyncIdentifier.parse("energy") == nil)
        #expect(SyncIdentifier.parse("not-a-uuid.energy") == nil)
        #expect(SyncIdentifier.parse("\(entryID.uuidString)") == nil)
        #expect(SyncIdentifier.parse("\(entryID.uuidString).") == nil)
        #expect(SyncIdentifier.parse("\(entryID.uuidString).caffeine") == nil)
        #expect(SyncIdentifier.parse("\(entryID.uuidString).energy.extra") == nil)
        #expect(SyncIdentifier.parse(".energy") == nil)
    }

    @Test func lowercaseUUIDStillNamesTheSameEntry() throws {
        let parsed = try #require(SyncIdentifier.parse("\(entryID.uuidString.lowercased()).fiber"))
        #expect(parsed.entryID == entryID)
        #expect(parsed.part == .nutrient(.fiber))
    }
}
