import Foundation
import Testing
@testable import Omnomnom

/// The one order the merged results are put in: what beats what, and why.
struct SearchRelevanceTests {
    private func score(_ name: String, _ query: String) -> Double {
        SearchRelevance.score(name: name, query: query)
    }

    @Test func foldingIgnoresCaseDiacriticsAndSpacing() {
        #expect(SearchRelevance.fold("  Pomme,   PULPE  ") == "pomme, pulpe")
        #expect(SearchRelevance.fold("Äpfel") == SearchRelevance.fold("apfel"))
        #expect(score("Pomme, pulpe et peau, crue", "POMME") > 0)
    }

    @Test func tiersRankInOrder() {
        // "Buttermilk" would be no use here: it starts with the query, so it is a
        // prefix match, not a substring one. "Chocolate" holds "cola" mid-word.
        let exact = score("Cola", "cola")
        let prefix = score("Cola, diet", "cola")
        let wordPrefix = score("Soft drink, cola", "cola")
        let substring = score("Chocolate", "cola")
        #expect(exact > prefix)
        #expect(prefix > wordPrefix)
        #expect(wordPrefix > substring)
        #expect(substring > 0)
    }

    @Test func nothingInCommonScoresZero() {
        #expect(score("Lentil soup", "butter") == 0)
        #expect(score("", "butter") == 0)
        #expect(score("Butter", "") == 0)
    }

    @Test func everyTokenMatchesOutOfOrder() {
        // "Rolled oats" answers "oats rolled", below a phrase match but above nothing.
        let outOfOrder = score("Rolled oats, old fashioned", "oats rolled")
        #expect(outOfOrder > 0)
        #expect(outOfOrder < score("Rolled oats, old fashioned", "rolled oats"))
    }

    @Test func aTokenMissingFromTheNameScoresZero() {
        #expect(score("Rolled oats", "oats rolled quickly") == 0)
    }

    @Test func aShorterNameWinsAtTheSameTier() {
        #expect(score("Apple raw", "apple") > score("Apple pie filling, canned", "apple"))
    }

    @Test func theBestOfARowsNamesCounts() {
        // A recipe filed under "breakfast" is a good answer to "breakfast".
        let best = SearchRelevance.score(anyOf: ["Overnight oats", "breakfast"], query: "breakfast")
        #expect(best == score("breakfast", "breakfast"))
        #expect(SearchRelevance.score(anyOf: [], query: "x") == 0)
    }

    @Test func aRowMatchedOnSomethingUnseenStillRanksAboveNothing() {
        // Open Food Facts also matches categories and labels, which are not requested.
        let rank = SearchRelevance.rank(anyOf: ["Nutella"], query: "kinder bueno", bonus: 0)
        #expect(rank == SearchRelevance.unexplained)
        #expect(rank > 0)
    }

    @Test func onlyCrowdsourcingIsWeighted() {
        #expect(SearchRelevance.bonus(isCrowdsourced: false) == 0)
        #expect(SearchRelevance.bonus(isCrowdsourced: true) == -SearchRelevance.crowdsourcedPenalty)
    }

    @Test func aBetterMatchAlwaysWins() {
        let names = ["Cola", "Cola, diet", "Soft drink, cola", "Chocolate"]
        for bonus in [0.0, -SearchRelevance.crowdsourcedPenalty] {
            let ranks = names.map { SearchRelevance.rank(anyOf: [$0], query: "cola", bonus: bonus) }
            #expect(ranks == ranks.sorted(by: >))
        }
    }

    /// A row Open Food Facts returned for a category this app never asked for has no
    /// explainable place in the list, and must stay under every row that does.
    @Test func anUnexplainedRowStaysUnderAnExplainedOne() {
        let unexplained = SearchRelevance.rank(
            anyOf: ["Nutella"], query: "kinder bueno", bonus: 0
        )
        let weakestExplained = SearchRelevance.everyToken - SearchRelevance.crowdsourcedPenalty
        #expect(unexplained < weakestExplained)
    }

    @Test func aMeasuredRowEdgesOutACrowdsourcedOneAtTheSameMatch() {
        let measured = SearchRelevance.rank(anyOf: ["Oat drink"], query: "oat", bonus: 0)
        let crowdsourced = SearchRelevance.rank(
            anyOf: ["Oat drink"], query: "oat",
            bonus: SearchRelevance.bonus(isCrowdsourced: true)
        )
        #expect(measured > crowdsourced)
    }
}

/// Splitting the results into the two groups they are shown in.
struct SearchSectionsTests {
    private func result(
        _ name: String, _ provenance: SearchResult.Provenance, rank: Double,
        lastUsed: Date? = nil, barcode: String? = nil
    ) -> SearchResult {
        let action: SearchResult.Action
        if let barcode {
            action = .fetch(ProductRecord(
                code: barcode, name: name, brand: nil,
                per100g: Nutrition(energy: 100, protein: 1, carbohydrates: 1, fatTotal: 1)
            ))
        } else {
            action = .choice(FoodChoice(
                source: .bundled(id: abs(name.hashValue % 1000)), name: name,
                perUnit: Nutrition(energy: 100)
            ))
        }
        return SearchResult(
            id: "\(provenance.pill)-\(name)", provenance: provenance, name: name,
            caption: "", photo: nil, rank: rank, lastUsed: lastUsed, action: action
        )
    }

    private func saved(_ name: String, barcode: String, rank: Double) -> SearchResult {
        SearchResult(
            id: "saved-\(barcode)", provenance: .openFoodFacts, name: name, caption: "",
            photo: nil, rank: rank, lastUsed: nil,
            action: .choice(FoodChoice(
                source: .product(foodID: UUID()), name: name, perUnit: Nutrition(energy: 100),
                attribution: ProductAttribution(barcode: barcode, brand: nil, source: .openFoodFacts)
            ))
        )
    }

    @Test func theUsersOwnFoodsStayOutOfTheRankedHalf() {
        let sections = SearchResults.sections(
            local: [result("Mine", .yours, rank: 0.1)],
            database: [result("Measured", .database, rank: 0.9)],
            products: [result("Branded", .openFoodFacts, rank: 0.6, barcode: "1")]
        )
        #expect(sections.yours.map(\.name) == ["Mine"])
        #expect(sections.others.map(\.name) == ["Measured", "Branded"])
    }

    @Test func whatWasEatenMostRecentlyComesFirst() {
        let old = Date(timeIntervalSinceReferenceDate: 1000)
        let recent = Date(timeIntervalSinceReferenceDate: 9000)
        let sections = SearchResults.sections(
            local: [
                result("Oatcakes", .yours, rank: 0.9, lastUsed: old),
                result("Overnight oats", .recipe, rank: 0.5, lastUsed: recent),
            ],
            database: [], products: []
        )
        // The better text match is the oatcakes; the answer is the porridge.
        #expect(sections.yours.map(\.name) == ["Overnight oats", "Oatcakes"])
    }

    @Test func whatHasNeverBeenEatenFollowsByMatch() {
        let sections = SearchResults.sections(
            local: [
                result("Never eaten, poor match", .recipe, rank: 0.3),
                result("Eaten once", .yours, rank: 0.1, lastUsed: Date(timeIntervalSinceReferenceDate: 1)),
                result("Never eaten, good match", .recipe, rank: 0.8),
            ],
            database: [], products: []
        )
        #expect(sections.yours.map(\.name)
            == ["Eaten once", "Never eaten, good match", "Never eaten, poor match"])
    }

    @Test func theBundledTablesAndTheNetworkAreOneRankedList() {
        let sections = SearchResults.sections(
            local: [],
            database: [result("Second", .database, rank: 0.5)],
            products: [
                result("First", .openFoodFacts, rank: 0.9, barcode: "1"),
                result("Third", .openFoodFacts, rank: 0.1, barcode: "2"),
            ]
        )
        #expect(sections.others.map(\.name) == ["First", "Second", "Third"])
    }

    @Test func tiesKeepTheOrderTheyWereGroupedIn() {
        let sections = SearchResults.sections(
            local: [],
            database: [result("A", .database, rank: 0.5), result("B", .database, rank: 0.5)],
            products: [result("C", .openFoodFacts, rank: 0.5, barcode: "1")]
        )
        #expect(sections.others.map(\.name) == ["A", "B", "C"])
    }

    @Test func aProductAlreadySavedIsNotOfferedTwice() {
        let sections = SearchResults.sections(
            local: [saved("Kinder Bueno", barcode: "8000500037560", rank: 0.9)],
            database: [],
            products: [
                result("Kinder Bueno", .openFoodFacts, rank: 0.95, barcode: "8000500037560"),
                result("Kinder Bueno Coconut", .openFoodFacts, rank: 0.8, barcode: "80960270"),
            ]
        )
        #expect(sections.yours.map(\.name) == ["Kinder Bueno"])
        #expect(sections.others.map(\.name) == ["Kinder Bueno Coconut"])
        // The saved copy is the one that survives, because it knows the last amount.
        if case .choice = sections.yours.first?.action {} else {
            Issue.record("the saved copy should be the one kept")
        }
    }

    @Test func nothingFoundIsAnEmptyPairOfGroups() {
        let sections = SearchResults.sections(local: [], database: [], products: [])
        #expect(sections.isEmpty)
        #expect(SearchResults.sections(
            local: [], database: [result("One", .database, rank: 0.5)], products: []
        ).isEmpty == false)
    }

    @Test func pillsNameTheSource() {
        #expect(SearchResult.Provenance.recipe.pill == "Recipe")
        #expect(SearchResult.Provenance.yours.pill == "Yours")
        #expect(SearchResult.Provenance.database.pill == "Database")
        #expect(SearchResult.Provenance.openFoodFacts.pill == "Open Food Facts")
    }
}
