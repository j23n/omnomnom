import Foundation
import Testing
@testable import Omnomnom

/// What a day was made of, including the part no macronutrient accounts for.
struct MacroCompositionTests {
    /// The day the design boards are drawn from: 63 g protein, 168 g carbohydrate, 41 g fat.
    private var typicalDay: Nutrition {
        Nutrition(energy: 1320, protein: 63, carbohydrates: 168, fatTotal: 41, fiber: 32)
    }

    @Test func macronutrientsAreConvertedAtFourFourAndNine() {
        let composition = MacroComposition(of: typicalDay)
        #expect(composition.protein == 252)
        #expect(composition.carbohydrates == 672)
        #expect(composition.fat == 369)
    }

    @Test func whatTheMacronutrientsDoNotAccountForIsKept() {
        // 252 + 672 + 369 is 1,293 against an energy figure of 1,320. The 27 is real and
        // is drawn rather than divided into the three that are known.
        let composition = MacroComposition(of: typicalDay)
        #expect(composition.unattributed == 27)
        #expect(composition.total == 1320)
    }

    @Test func sharesAreTakenAgainstTheWhole() {
        let composition = MacroComposition(of: typicalDay)
        #expect(abs(composition.share(of: .protein) - 0.1909) < 0.001)
        #expect(abs(composition.share(of: .carbohydrates) - 0.5091) < 0.001)
        #expect(abs(composition.share(of: .fatTotal) - 0.2795) < 0.001)
        #expect(abs(composition.unattributedShare - 0.0205) < 0.001)
    }

    @Test func sharesAlwaysSumToOne() {
        let composition = MacroComposition(of: typicalDay)
        let sum = composition.bands.reduce(0) { $0 + $1.share }
        #expect(abs(sum - 1) < 0.0001)
    }

    // MARK: - The two directions of disagreement

    @Test func energyLowerThanTheMacronutrientsImplyGivesWay() {
        // 10 g protein, 10 g carbohydrate and 5 g fat come to 125 kcal against a stated
        // 100. Shrinking the measured macronutrients to fit would be inventing a
        // correction, so the denominator moves instead and there is no gap to draw.
        let composition = MacroComposition(
            of: Nutrition(energy: 100, protein: 10, carbohydrates: 10, fatTotal: 5)
        )
        #expect(composition.total == 125)
        #expect(composition.unattributed == 0)
        let sum = composition.bands.reduce(0) { $0 + $1.share }
        #expect(abs(sum - 1) < 0.0001)
    }

    @Test func aNegativeAmountCannotPullAShareBelowZero() {
        let composition = MacroComposition(
            of: Nutrition(energy: 100, protein: -5, carbohydrates: 10, fatTotal: 1)
        )
        #expect(composition.protein == 0)
        #expect(composition.share(of: .protein) == 0)
    }

    // MARK: - Missing figures

    @Test func aMacronutrientWithNoFigureIsNamedRatherThanTreatedAsZero() {
        // Apple juice really has no fat figure in the bundled table. Its share is zero
        // either way; the difference is that this says so, and a bar drawn from it hatches.
        let composition = MacroComposition(
            of: Nutrition(energy: 110, protein: 0.3, carbohydrates: 26.5, fatTotal: nil)
        )
        #expect(composition.missing == [.fatTotal])
        #expect(composition.fat == 0)
    }

    @Test func nothingKnownIsEmptyAndNamesAllThree() {
        let composition = MacroComposition(of: .empty)
        #expect(composition.isEmpty)
        #expect(composition.total == 0)
        #expect(composition.missing == [.protein, .carbohydrates, .fatTotal])
        #expect(composition.bands.isEmpty)
    }

    @Test func anEmptyDayHasNoBandsAndNoMissingFigures() {
        // Every nutrient is present and zero, which is a different fact from unknown.
        let composition = MacroComposition(of: .zero)
        #expect(composition.isEmpty)
        #expect(composition.missing.isEmpty)
        #expect(composition.bands.isEmpty)
        #expect(composition.share(of: .protein) == 0)
    }

    // MARK: - Bands

    @Test func bandsKeepTheirOrderWhateverTheDayLooksLike() {
        // Butter: almost all fat. Protein still comes first, because a band that moves
        // between days cannot be read across them.
        let composition = MacroComposition(
            of: Nutrition(energy: 732, protein: 1.2, carbohydrates: 0.6, fatTotal: 80.6)
        )
        #expect(composition.bands.map(\.nutrient) == [.protein, .carbohydrates, .fatTotal])
    }

    @Test func aMacronutrientContributingNothingIsNotDrawnAsASliver() {
        // Gouda has no carbohydrate at all, so there is no carbohydrate band to draw.
        let composition = MacroComposition(
            of: Nutrition(energy: 379, protein: 22.5, carbohydrates: 0, fatTotal: 31.6)
        )
        #expect(composition.bands.map(\.nutrient) == [.protein, .fatTotal])
    }

    @Test func theUnaccountedBandComesLastAndHasNoNutrient() {
        let composition = MacroComposition(of: typicalDay)
        #expect(composition.bands.count == 4)
        #expect(composition.bands.last?.nutrient == nil)
        #expect(composition.bands.last?.kilocalories == 27)
        #expect(composition.bands.last?.id == "unattributed")
    }

    @Test func aBandOnlyEverCarriesAMacronutrient() {
        // Fibre has energy in reality and none here: the three bands are the whole of it,
        // and anything fibre contributes falls into the unaccounted part by construction.
        let composition = MacroComposition(of: typicalDay)
        #expect(composition.kilocalories(of: .fiber) == 0)
        #expect(composition.share(of: .energy) == 0)
    }
}
