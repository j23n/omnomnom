import Foundation
import Testing
@testable import Omnomnom

/// The flow's decision table, without a store: what the cache and the lookup say
/// determines the step, and the reasons are the sentences the editor shows.
struct BarcodeLookupFlowTests {
    private let code = "4006381333931"
    private let record = ProductRecord(
        code: "4006381333931", name: "Nutella", brand: "Ferrero", per100g: Nutrition(energy: 539, protein: 6.3)
    )
    private let cached = FoodChoice(
        source: .product(foodID: UUID()), name: "Nutella", perUnit: Nutrition(energy: 539),
        attribution: ProductAttribution(barcode: "4006381333931", brand: "Ferrero", source: .openFoodFacts)
    )

    @Test func cacheHitWinsWhateverTheNetworkSaid() {
        #expect(BarcodeLookupFlow.step(code: code, cached: cached, lookup: nil) == .found(cached))
        #expect(BarcodeLookupFlow.step(code: code, cached: cached, lookup: .failure(.decoding)) == .found(cached))
        #expect(BarcodeLookupFlow.step(code: code, cached: cached, lookup: .success(nil)) == .found(cached))
    }

    @Test func usableRecordIsCached() {
        #expect(BarcodeLookupFlow.step(code: code, cached: nil, lookup: .success(record)) == .cache(record))
    }

    @Test func missGoesManualWithoutAName() {
        let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: .success(nil))
        #expect(step == .manual(barcode: code, prefillName: nil, measure: .mass, reason: "Not on Open Food Facts"))
    }

    @Test func recordWithoutEnergyGoesManualWithTheName() {
        let bare = ProductRecord(code: code, name: "Nutella", brand: "Ferrero", per100g: Nutrition(protein: 6.3))
        let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: .success(bare))
        #expect(step == .manual(
            barcode: code, prefillName: "Nutella", measure: .mass,
            reason: "No nutrition values on Open Food Facts"
        ))
    }

    /// A drink the label describes but Open Food Facts has no values for still opens the
    /// editor in millilitres: the unit was on the label, only the nutrition was missing.
    @Test func recordWithoutEnergyKeepsTheUnitItWasMeasuredIn() {
        let drink = ProductRecord(
            code: code, name: "Oat drink", brand: "Oatly", per100g: .empty, measure: .volume
        )
        let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: .success(drink))
        #expect(step == .manual(
            barcode: code, prefillName: "Oat drink", measure: .volume,
            reason: "No nutrition values on Open Food Facts"
        ))
    }

    @Test func networkFailureSaysNoConnection() {
        let lookup = BarcodeLookupFlow.Lookup.failure(.network(URLError(.notConnectedToInternet)))
        let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: lookup)
        #expect(step == .manual(barcode: code, prefillName: nil, measure: .mass, reason: "No connection"))
    }

    @Test func otherFailuresSayLookupFailed() {
        for failure in [OpenFoodFactsError.http(500), .decoding, .invalidBarcode] {
            let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: .failure(failure))
            #expect(step == .manual(barcode: code, prefillName: nil, measure: .mass, reason: "Lookup failed"))
        }
    }

    @Test func skippedLookupSaysTheModuleIsOff() {
        let step = BarcodeLookupFlow.step(code: code, cached: nil, lookup: nil)
        #expect(step == .manual(barcode: code, prefillName: nil, measure: .mass, reason: "Barcode lookup is off"))
    }
}
