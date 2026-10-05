import Foundation
import Testing
@testable import Omnomnom

/// What the mark and the bar say about a day, which is the part of a view worth testing:
/// the sentences a screen reader reads and the geometry the ticks are placed by.
struct CompositionViewTests {
    /// The day the design boards are drawn from.
    private var typicalDay: Nutrition {
        Nutrition(energy: 1320, protein: 63, carbohydrates: 168, fatTotal: 41, fiber: 32)
    }

    private var composition: MacroComposition { MacroComposition(of: typicalDay) }

    // MARK: - The mark

    @Test func anEmptyDaySaysSoAndNothingElse() {
        let spoken = DayMarkView.label(answers: .empty, composition: .empty, isAssumed: false)
        #expect(spoken == "No meals answered yet.")
    }

    @Test func theMarkCountsTheMealsAnsweredRatherThanDividingThem() {
        let answers = DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack])
        let spoken = DayMarkView.label(answers: answers, composition: composition, isAssumed: false)
        #expect(spoken.hasPrefix("3 of 4 meals answered."))
        // Named, never divided: no percentage of the day, no ratio, no progress.
        #expect(!spoken.contains("75"))
    }

    @Test func aFullDaySaysAllOfThemAndAnAcceptedOneSaysWhereItCameFrom() {
        let all = DayAnswers(logged: Set(MealSlot.allCases))
        #expect(
            DayMarkView.label(answers: all, composition: composition, isAssumed: false)
                .hasPrefix("All 4 meals answered.")
        )
        #expect(
            DayMarkView.label(answers: all, composition: composition, isAssumed: true)
                .hasPrefix("All 4 meals, from your usual day.")
        )
    }

    @Test func theMarkReadsItsBandsInTheOrderTheyAreDrawn() {
        // Not in order of size: a band that moves between days cannot be read across them.
        let answers = DayAnswers(logged: [.breakfast])
        let spoken = DayMarkView.label(answers: answers, composition: composition, isAssumed: false)
        #expect(spoken.contains("Protein 19 per cent, Carbohydrates 51 per cent, Fat 28 per cent"))
        #expect(spoken.contains("not attributed 2 per cent"))
    }

    // MARK: - The bar

    @Test func theBarReadsLargestFirst() {
        // The spoken order is the other way round from the drawn order on purpose: a list
        // read aloud is easier to take in biggest-first, and it carries no position to
        // compare across days the way a drawn band does.
        #expect(
            CompositionBar.label(composition)
                == "Carbohydrates 51 per cent, Fat 28 per cent, Protein 19 per cent, not attributed 2 per cent."
        )
    }

    @Test func anEmptyBarSaysNothingIsLogged() {
        #expect(CompositionBar.label(.empty) == "Nothing logged yet.")
    }

    @Test func ticksSitAtTheBoundariesBetweenBandsAndNotAtTheEnds() {
        let boundaries = CompositionBar.boundaries(of: composition)
        #expect(boundaries.count == 3)
        #expect(abs(boundaries[0] - 0.1909) < 0.001)
        #expect(abs(boundaries[1] - 0.7000) < 0.001)
        #expect(abs(boundaries[2] - 0.9795) < 0.001)
        // The right-hand edge is not a mark.
        #expect(!boundaries.contains { $0 >= 1 })
    }

    @Test func aBarWithOneBandHasNoBoundaries() {
        let single = MacroComposition(of: Nutrition(energy: 400, protein: 100, carbohydrates: 0, fatTotal: 0))
        #expect(CompositionBar.boundaries(of: single).isEmpty)
    }

    @Test func anEmptyCompositionHasNoBoundaries() {
        #expect(CompositionBar.boundaries(of: .empty).isEmpty)
    }

    // MARK: - The legend

    @Test func sharesAreWholeNumbers() {
        #expect(CompositionLegend.share(0.509) == "51 %")
        #expect(CompositionLegend.share(0) == "0 %")
        #expect(CompositionLegend.share(1) == "100 %")
    }

    @Test func aMissingFigureIsNamedAndItsTotalCalledAFloor() {
        #expect(
            CompositionLegend.missingNote([.fatTotal])
                == "Some of this has no figure for fat, so that total is a floor."
        )
    }

    @Test func severalMissingFiguresAreNamedInTheirOwnDisplayOrder() {
        // Never in order of how much is missing, which would be a judgement about which
        // gap matters.
        #expect(
            CompositionLegend.missingNote([.sodium, .fiber])
                == "Some of this has no figure for fiber and sodium, so those totals are a floor."
        )
    }
}
