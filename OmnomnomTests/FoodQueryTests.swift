import Testing
@testable import Omnomnom

struct FoodQueryTests {
    @Test func emptyAndWhitespaceYieldNil() {
        #expect(FoodQuery.ftsMatchExpression(for: "") == nil)
        #expect(FoodQuery.ftsMatchExpression(for: "   \n\t") == nil)
    }

    @Test func singleTokenIsQuotedAndPrefixed() {
        #expect(FoodQuery.ftsMatchExpression(for: "apple") == "\"apple\"*")
    }

    @Test func tokensAreSplitOnAnyWhitespace() {
        #expect(FoodQuery.ftsMatchExpression(for: "  chicken   breast\troasted ") == "\"chicken\"* \"breast\"* \"roasted\"*")
    }

    @Test func internalQuotesAreDoubled() {
        #expect(FoodQuery.ftsMatchExpression(for: "3\" dia") == "\"3\"\"\"* \"dia\"*")
    }

    @Test func ftsOperatorsAreNeutralisedByQuoting() {
        #expect(FoodQuery.ftsMatchExpression(for: "apple OR NOT*") == "\"apple\"* \"OR\"* \"NOT*\"*")
        #expect(FoodQuery.ftsMatchExpression(for: "(milk)") == "\"(milk)\"*")
    }
}
