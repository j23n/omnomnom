import Foundation
import Testing
@testable import Omnomnom

/// FTS5 expressions, including the plural problem that made the most ordinary breakfast
/// in the German table unreachable.
struct FoodQueryTests {
    @Test func oneTokenIsAQuotedPrefixTerm() {
        #expect(FoodQuery.ftsMatchExpression(for: "apple") == "\"apple\"*")
    }

    @Test func tokensAreAndedTogether() {
        #expect(FoodQuery.ftsMatchExpression(for: "peanut butter") == "\"peanut\"* AND \"butter\"*")
    }

    @Test func blankTextHasNoExpression() {
        #expect(FoodQuery.ftsMatchExpression(for: "") == nil)
        #expect(FoodQuery.ftsMatchExpression(for: "   ") == nil)
    }

    @Test func quotesAreDoubledSoTheyCannotCloseTheTerm() {
        #expect(FoodQuery.ftsMatchExpression(for: "6\" sub") == "\"6\"\"\"* AND \"sub\"*")
    }

    // MARK: - Plurals

    @Test func aPluralIsSearchedInBothForms() {
        // FTS5's prefix match runs forwards only: "oat"* finds "Oat flakes" and "oats"*
        // finds nothing. The German table calls the food "Oat flakes".
        #expect(FoodQuery.forms(of: "oats") == ["oats", "oat"])
        #expect(FoodQuery.ftsMatchExpression(for: "oats") == "(\"oats\"* OR \"oat\"*)")
    }

    @Test func anEsPluralDropsBothEndings() {
        #expect(FoodQuery.forms(of: "tomatoes") == ["tomatoes", "tomato", "tomatoe"])
    }

    @Test func aShortWordIsLeftAlone() {
        // "as", "is", "gas": dropping the s would search for a letter.
        #expect(FoodQuery.forms(of: "gas") == ["gas"])
        #expect(FoodQuery.forms(of: "as") == ["as"])
    }

    @Test func adoubleSIsNotAPlural() {
        #expect(FoodQuery.forms(of: "cress") == ["cress"])
        #expect(FoodQuery.forms(of: "glass") == ["glass"])
    }

    @Test func aSingularIsLeftAlone() {
        #expect(FoodQuery.forms(of: "oat") == ["oat"])
        #expect(FoodQuery.forms(of: "banana") == ["banana"])
    }

    @Test func everyJoinIsAnExplicitAnd() {
        // FTS5's implicit AND rejects a group beside a bare term, so the operator is
        // always spelled out. Verified against the real index, not assumed.
        #expect(
            FoodQuery.ftsMatchExpression(for: "oat flakes")
                == "\"oat\"* AND (\"flakes\"* OR \"flake\"*)"
        )
    }

    @Test func aMixedQueryClausesEachTokenOnItsOwnTerms() {
        #expect(
            FoodQuery.ftsMatchExpression(for: "oats banana")
                == "(\"oats\"* OR \"oat\"*) AND \"banana\"*"
        )
    }

    @Test func caseDoesNotDecideWhetherSomethingIsAPlural() {
        #expect(FoodQuery.forms(of: "OATS") == ["OATS", "OAT"])
    }
}
