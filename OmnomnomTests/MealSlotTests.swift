import Testing
@testable import Omnomnom

struct MealSlotTests {
    @Test func everySlotHasItsOwnSymbol() {
        let names = MealSlot.allCases.map(\.symbolName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func symbolsAreTheDecidedOnes() {
        #expect(MealSlot.breakfast.symbolName == "sunrise")
        #expect(MealSlot.lunch.symbolName == "sun.max")
        #expect(MealSlot.dinner.symbolName == "moon.stars")
        #expect(MealSlot.snack.symbolName == "carrot")
    }
}
