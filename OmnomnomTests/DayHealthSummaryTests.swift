import Foundation
import Testing
@testable import Omnomnom

struct DayHealthSummaryTests {
    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let localEntry = UUID()

    /// `own` gives the sample this app's bundle and, unless `entry` is set, an identifier
    /// for `localEntry`; `entry` names another entry, `identifier` overrides the identifier.
    private func sample(
        _ nutrient: Nutrient, _ value: Double, at date: Date, own: Bool = false, entry: UUID? = nil,
        identifier: String? = nil, source: String = "Other App", foodType: String? = nil
    ) -> HealthNutritionSample {
        let ownIdentifier = SyncIdentifier.make(entryID: entry ?? localEntry, nutrient: nutrient)
        return HealthNutritionSample(
            nutrient: nutrient, value: value, start: date, isOwnBundle: own, sourceName: own ? "Omnomnom" : source,
            syncIdentifier: identifier ?? (own ? ownIdentifier : nil), foodType: foodType
        )
    }

    private func make(_ samples: [HealthNutritionSample]) -> DayHealthSummary {
        DayHealthSummary.make(from: samples, localEntryIDs: [localEntry])
    }

    @Test func emptyInputIsEmpty() {
        let summary = make([])
        #expect(summary == .empty)
        #expect(!summary.hasForeign)
        #expect(summary.meals.isEmpty)
    }

    @Test func ownAndForeignAreSummedSeparately() {
        let summary = make([
            sample(.energy, 100, at: noon, own: true),
            sample(.protein, 5, at: noon, own: true),
            sample(.energy, 250, at: noon, foodType: "Oatmeal"),
            sample(.energy, 50, at: noon.addingTimeInterval(3600), foodType: "Apple"),
        ])
        #expect(summary.own.energy == 100)
        #expect(summary.own.protein == 5)
        #expect(summary.own.sodium == nil)
        #expect(summary.foreign.energy == 300)
        #expect(summary.foreign.protein == nil)
        #expect(summary.hasForeign)
        #expect(summary.meals.map(\.name) == ["Oatmeal", "Apple"])
    }

    @Test func mealsGroupByNameSourceAndMinute() {
        let sameMinute = noon.addingTimeInterval(20)
        let summary = make([
            sample(.energy, 200, at: noon, foodType: "Oatmeal"),
            sample(.protein, 6, at: sameMinute, foodType: "Oatmeal"),
            sample(.energy, 200, at: noon, source: "Another App", foodType: "Oatmeal"),
            sample(.energy, 10, at: noon.addingTimeInterval(60), foodType: "Oatmeal"),
        ])
        #expect(summary.meals.count == 3)
        let first = summary.meals[0]
        #expect(first.name == "Oatmeal")
        #expect(first.start == DayHealthSummary.minute(of: noon))
        #expect(summary.meals.map(\.sourceName) == ["Another App", "Other App", "Other App"])
        let grouped = summary.meals.first { $0.sourceName == "Other App" && $0.start == DayHealthSummary.minute(of: noon) }
        #expect(grouped?.nutrition.energy == 200)
        #expect(grouped?.nutrition.protein == 6)
        #expect(summary.foreign.energy == 410)
        #expect(Set(summary.meals.map(\.id)).count == 3)
    }

    @Test func sourceNameStandsInForAMissingFoodType() {
        let summary = make([
            sample(.energy, 120, at: noon, source: "Health"),
            sample(.carbohydrates, 30, at: noon, source: "Health"),
        ])
        #expect(summary.meals.count == 1)
        #expect(summary.meals.first?.name == "Health")
        #expect(summary.meals.first?.nutrition.carbohydrates == 30)
    }

    @Test func zeroForeignAmountsDoNotCountAsForeign() {
        let summary = make([sample(.energy, 0, at: noon)])
        #expect(!summary.hasForeign)
        #expect(summary.meals.count == 1)
    }

    @Test func localMirroredSamplesAreOwnNotForeign() {
        let summary = make([sample(.energy, 300, at: noon, own: true)])
        #expect(summary.own.energy == 300)
        #expect(summary.foreign.energy == nil)
        #expect(!summary.hasForeign)
        #expect(summary.meals.isEmpty)
    }

    @Test func thisAppWithoutALocalEntryIsForeignAndLabelled() {
        let elsewhere = UUID()
        let summary = make([
            sample(.energy, 180, at: noon, own: true, entry: elsewhere, foodType: "Rye bread"),
            sample(.protein, 4, at: noon, own: true, entry: elsewhere, foodType: "Rye bread"),
            sample(.energy, 90, at: noon.addingTimeInterval(120), own: true, entry: UUID()),
        ])
        #expect(summary.own.energy == nil)
        #expect(summary.foreign.energy == 270)
        #expect(summary.hasForeign)
        #expect(summary.meals.count == 2)
        #expect(summary.meals[0].name == "Rye bread · \(DayHealthSummary.unmirroredLabel)")
        #expect(summary.meals[0].sourceName == "Omnomnom")
        #expect(summary.meals[0].nutrition.protein == 4)
        #expect(summary.meals[1].name == DayHealthSummary.unmirroredLabel)
    }

    @Test func ownBundleWithUnparseableIdentifierIsForeign() {
        let summary = make([
            sample(.energy, 75, at: noon, own: true, identifier: "not-ours", foodType: "Toast"),
            sample(.energy, 25, at: noon, own: true, identifier: "\(localEntry.uuidString).caffeine"),
        ])
        #expect(summary.own.energy == nil)
        #expect(summary.foreign.energy == 100)
        #expect(summary.meals.map(\.name) == [DayHealthSummary.unmirroredLabel, "Toast · \(DayHealthSummary.unmirroredLabel)"])
    }

    @Test func minuteRoundsDown() {
        let date = Date(timeIntervalSinceReferenceDate: 119)
        #expect(DayHealthSummary.minute(of: date) == Date(timeIntervalSinceReferenceDate: 60))
    }
}
