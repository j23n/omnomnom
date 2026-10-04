import Foundation
import Testing
@testable import Omnomnom

/// Which three figures sit beside energy, which is the user's choice and not the app's.
struct HeadlineNutrientsTests {
    @Test func theStandardSetIsTheFourSpreadAcrossMostFoods() {
        // Energy, protein, carbohydrates and fat: the four a portion bucket disturbs
        // least, because they come from nearly everything anyone eats.
        #expect(HeadlineNutrients.standard == [.protein, .carbohydrates, .fatTotal])
    }

    @Test func aRoundTripKeepsTheSelection() {
        let chosen: [Nutrient] = [.fiber, .sugar, .sodium]
        #expect(HeadlineNutrients.decode(HeadlineNutrients.encode(chosen)) == chosen)
    }

    @Test func nothingStoredFallsBackToTheStandardSet() {
        #expect(HeadlineNutrients.decode("") == HeadlineNutrients.standard)
    }

    @Test func energyIsNeverPartOfTheChoice() {
        #expect(!HeadlineNutrients.selectable.contains(.energy))
        #expect(!HeadlineNutrients.decode("energy,fiber,sugar,sodium").contains(.energy))
    }

    @Test func anUnknownNameIsDroppedRatherThanBreakingTheRow() {
        let decoded = HeadlineNutrients.decode("fiber,somethingNew,sugar")
        #expect(decoded.count == HeadlineNutrients.count)
        #expect(decoded.prefix(2) == [.fiber, .sugar])
    }

    @Test func tooFewIsPaddedAndTooManyIsCapped() {
        #expect(HeadlineNutrients.decode("fiber").count == HeadlineNutrients.count)
        #expect(HeadlineNutrients.decode("fiber,sugar,sodium,protein,fatTotal").count == HeadlineNutrients.count)
    }

    @Test func aRepeatedNameIsNotCountedTwice() {
        let decoded = HeadlineNutrients.decode("fiber,fiber,fiber")
        #expect(decoded.count == HeadlineNutrients.count)
        #expect(Set(decoded).count == HeadlineNutrients.count)
    }

    @Test func theSecondaryRowIsEverythingElseAndAllEightStayVisible() {
        let large = HeadlineNutrients.standard
        let small = HeadlineNutrients.secondary(to: large)
        #expect(small.count == 4)
        #expect(Set(large).isDisjoint(with: Set(small)))
        #expect(Set(large + small + [.energy]) == Set(Nutrient.allCases))
    }
}
