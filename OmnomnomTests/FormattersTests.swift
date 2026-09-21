import Testing
@testable import Omnomnom

struct FormattersTests {
    @Test func parseGramsAcceptsCommaAndTrimsWhitespace() {
        #expect(Formatters.parseGrams(" 62,5 ") == 62.5)
        #expect(Formatters.parseGrams("182") == 182)
    }

    @Test func parseGramsRejectsGarbageAndOutOfRange() {
        #expect(Formatters.parseGrams("") == nil)
        #expect(Formatters.parseGrams("abc") == nil)
        #expect(Formatters.parseGrams("0") == nil)
        #expect(Formatters.parseGrams("0.05") == nil)
        #expect(Formatters.parseGrams("5000.1") == nil)
        #expect(Formatters.parseGrams("inf") == nil)
        #expect(Formatters.parseGrams("0.1") == 0.1)
        #expect(Formatters.parseGrams("5000") == 5000)
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

    @Test func rangeTextsNameTheUnit() {
        #expect(Formatters.gramsRangeText.hasSuffix(" and 5000 g"))
        #expect(Formatters.servingsRangeText.hasSuffix(" and 50 servings"))
    }

    @Test func fieldTextDropsTrailingZeroAndGrouping() {
        #expect(Formatters.fieldText(100) == "100")
        #expect(Formatters.fieldText(1500) == "1500")
        #expect(Formatters.parseGrams(Formatters.fieldText(62.5)) == 62.5)
    }
}
