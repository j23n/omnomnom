import Foundation
import Testing
@testable import Omnomnom

struct FormattersTests {
    @Test func parseAmountAcceptsCommaAndTrimsWhitespace() {
        #expect(Formatters.parseAmount(" 62,5 ") == 62.5)
        #expect(Formatters.parseAmount("182") == 182)
    }

    @Test func parseAmountRejectsGarbageAndOutOfRange() {
        #expect(Formatters.parseAmount("") == nil)
        #expect(Formatters.parseAmount("abc") == nil)
        #expect(Formatters.parseAmount("0") == nil)
        #expect(Formatters.parseAmount("0.05") == nil)
        #expect(Formatters.parseAmount("5000.1") == nil)
        #expect(Formatters.parseAmount("inf") == nil)
        #expect(Formatters.parseAmount("0.1") == 0.1)
        #expect(Formatters.parseAmount("5000") == 5000)
    }

    @Test func parseServingsAcceptsFractionsWithinRange() {
        #expect(Formatters.parseServings("0.5") == 0.5)
        #expect(Formatters.parseServings("1,5") == 1.5)
        #expect(Formatters.parseServings("50") == 50)
        #expect(Formatters.parseServings("0.1") == 0.1)
        #expect(Formatters.parseServings("0") == nil)
        #expect(Formatters.parseServings("0.05") == nil)
        #expect(Formatters.parseServings("50.5") == nil)
        #expect(Formatters.parseServings("") == nil)
        #expect(Formatters.parseServings("nan") == nil)
    }

    @Test func parseNutrientValueAllowsZeroAndRejectsNegatives() {
        #expect(Formatters.parseNutrientValue("0") == 0)
        #expect(Formatters.parseNutrientValue("389") == 389)
        #expect(Formatters.parseNutrientValue("0,5") == 0.5)
        #expect(Formatters.parseNutrientValue("-1") == nil)
        #expect(Formatters.parseNutrientValue("100001") == nil)
        #expect(Formatters.parseNutrientValue("x") == nil)
    }

    /// Whole numbers only: decimal separators depend on the test host's locale.
    @Test func servingsTextSingularAndPlural() {
        #expect(Formatters.servings(1) == "1 serving")
        #expect(Formatters.servings(2) == "2 servings")
        #expect(Formatters.servings(0.5).hasSuffix(" servings"))
    }

    @Test func wholeAmountRoundsToTheUnitAndNamesIt() {
        #expect(Formatters.wholeAmount(350, measure: .mass) == "350 g")
        #expect(Formatters.wholeAmount(350.4, measure: .mass) == "350 g")
        #expect(Formatters.wholeAmount(350.6, measure: .mass) == "351 g")
        #expect(Formatters.wholeAmount(250, measure: .volume) == "250 ml")
        #expect(Formatters.wholeAmount(249.5, measure: .volume) == "250 ml")
    }

    /// Whole numbers only where the text is compared: the decimal separator is the host's.
    @Test func amountKeepsOneDecimalAndNamesTheUnit() {
        #expect(Formatters.amount(182, measure: .mass) == "182 g")
        #expect(Formatters.amount(250, measure: .volume) == "250 ml")
        #expect(Formatters.amount(62.5, measure: .mass).hasSuffix(" g"))
        #expect(Formatters.amount(62.5, measure: .volume).hasSuffix(" ml"))
    }

    @Test func spokenAmountNamesTheUnitOrSaysNotRecorded() {
        #expect(Formatters.spokenAmount(92, unit: .gram) == "92 grams")
        #expect(Formatters.spokenAmount(nil, unit: .kilocalorie) == "not recorded")
    }

    @Test func dayTitleIsRelativeNearToday() {
        #expect(Formatters.dayTitle(.now) == "Today")
        let calendar = Calendar.current
        #expect(Formatters.dayTitle(calendar.date(byAdding: .day, value: -1, to: .now) ?? .now) == "Yesterday")
        #expect(Formatters.dayTitle(calendar.date(byAdding: .day, value: 1, to: .now) ?? .now) == "Tomorrow")
    }

    @Test func rangeTextsNameTheUnit() {
        #expect(Formatters.amountRangeText(measure: .mass).hasSuffix(" and 5000 g"))
        #expect(Formatters.amountRangeText(measure: .volume).hasSuffix(" and 5000 ml"))
        #expect(Formatters.servingsRangeText.hasSuffix(" and 50 servings"))
    }

    @Test func fieldTextDropsTrailingZeroAndGrouping() {
        #expect(Formatters.fieldText(100) == "100")
        #expect(Formatters.fieldText(1500) == "1500")
        #expect(Formatters.parseAmount(Formatters.fieldText(62.5)) == 62.5)
    }

    /// Whole results only where the text is compared: the decimal separator is the host's.
    @Test func prefillTextRoundsToOneDecimalAndKeepsWholeAmountsWhole() {
        #expect(Formatters.prefillText(30) == "30")
        #expect(Formatters.prefillText(30.0) == "30")
        #expect(Formatters.prefillText(33.96) == "34")
        #expect(Formatters.prefillText(1500) == "1500")
        #expect(Formatters.parseAmount(Formatters.prefillText(33.94)) == 33.9)
        #expect(Formatters.parseAmount(Formatters.prefillText(350.625)) == 350.6)
        #expect(Formatters.parseServings(Formatters.prefillText(1.5)) == 1.5)
    }
}
