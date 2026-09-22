import Testing
@testable import Omnomnom

struct FoodMeasureTests {
    @Test func symbolsAndReferencesNameTheUnit() {
        #expect(FoodMeasure.mass.unitSymbol == "g")
        #expect(FoodMeasure.volume.unitSymbol == "ml")
        #expect(FoodMeasure.mass.referenceUnit == "100 g")
        #expect(FoodMeasure.volume.referenceUnit == "100 ml")
        #expect(FoodMeasure.mass.referenceText == "per 100 g")
        #expect(FoodMeasure.volume.referenceText == "per 100 ml")
    }

    @Test func voiceOverAndPickerSpellTheUnitOut() {
        #expect(FoodMeasure.mass.spokenName == "grams")
        #expect(FoodMeasure.volume.spokenName == "millilitres")
        #expect(FoodMeasure.mass.displayName == "Grams")
        #expect(FoodMeasure.volume.displayName == "Millilitres")
    }

    /// The raw values are stored on `Food`, `LogEntry` and `RecipeIngredient`; changing
    /// one would silently reinterpret every row written before.
    @Test func rawValuesAreStableAndMassIsTheFallback() {
        #expect(FoodMeasure.mass.rawValue == "mass")
        #expect(FoodMeasure.volume.rawValue == "volume")
        #expect(FoodMeasure(rawValue: "volume") == .volume)
        #expect(FoodMeasure(rawValue: "litres") == nil)
        #expect(FoodMeasure.allCases == [.mass, .volume])
    }
}
