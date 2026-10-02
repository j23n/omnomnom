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

    @Test func bonusesFavourWhatTheUserOwnsAndHasLogged() {
        #expect(SearchRelevance.bonus(isLocal: true, isCrowdsourced: false, isFamiliar: false)
            == SearchRelevance.ownBonus)
        #expect(SearchRelevance.bonus(isLocal: false, isCrowdsourced: false, isFamiliar: false) == 0)
        // A saved product counts as the user's own however it got there.
        #expect(SearchRelevance.bonus(isLocal: true, isCrowdsourced: true, isFamiliar: false)
            == SearchRelevance.ownBonus)
        #expect(SearchRelevance.bonus(isLocal: false, isCrowdsourced: true, isFamiliar: false)
            == -SearchRelevance.crowdsourcedPenalty)
        #expect(SearchRelevance.bonus(isLocal: true, isCrowdsourced: false, isFamiliar: true)
            == SearchRelevance.ownBonus + SearchRelevance.familiarBonus)
    }

    @Test func aBetterMatchAlwaysWinsAtTheSameProvenance() {
        let names = ["Cola", "Cola, diet", "Soft drink, cola", "Chocolate"]
        for bonus in [0.0, SearchRelevance.ownBonus,
                      SearchRelevance.ownBonus + SearchRelevance.familiarBonus] {
            let ranks = names.map { SearchRelevance.rank(anyOf: [$0], query: "cola", bonus: bonus) }
            #expect(ranks == ranks.sorted(by: >))
        }
    }

    /// The one thing a bonus must never do. A row Open Food Facts returned for a
    /// category this app never asked for has no explainable place in the list, and no
    /// amount of "it is yours and you have logged it" may lift it over a row that does.
    /// The margin is one hundredth; raise a bonus and this test says so.
    @Test func aBonusNeverInventsAMatch() {
        let bestUnexplained = SearchRelevance.rank(
            anyOf: ["Nutella"], query: "kinder bueno",
            bonus: SearchRelevance.bonus(isLocal: true, isCrowdsourced: false, isFamiliar: true)
        )
        let weakestExplained = SearchRelevance.everyToken - SearchRelevance.crowdsourcedPenalty
        #expect(bestUnexplained < weakestExplained)
    }

    @Test func aWeakLocalMatchDoesNotBeatAStrongDatabaseOne() {
        let local = SearchRelevance.rank(
            anyOf: ["Pineapple juice"], query: "apple",
            bonus: SearchRelevance.bonus(isLocal: true, isCrowdsourced: false, isFamiliar: true)
        )
        let database = SearchRelevance.rank(
            anyOf: ["Apple raw"], query: "apple",
            bonus: SearchRelevance.bonus(isLocal: false, isCrowdsourced: false, isFamiliar: false)
        )
        #expect(database > local)
    }

    @Test func aFamiliarRecipeBeatsADatabaseRowThatMerelyStartsTheSame() {
        let recipe = SearchRelevance.rank(
            anyOf: ["Overnight oats"], query: "oat",
            bonus: SearchRelevance.bonus(isLocal: true, isCrowdsourced: false, isFamiliar: true)
        )
        let database = SearchRelevance.rank(
            anyOf: ["Oat whole grain, raw"], query: "oat",
            bonus: SearchRelevance.bonus(isLocal: false, isCrowdsourced: false, isFamiliar: false)
        )
        #expect(recipe > database)
    }
}

/// Merging the three halves into one list.
struct SearchResultsMergeTests {
    private func result(
        _ name: String, _ provenance: SearchResult.Provenance, rank: Double, barcode: String? = nil
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
            caption: "", photo: nil, rank: rank, action: action
        )
    }

    private func saved(_ name: String, barcode: String, rank: Double) -> SearchResult {
        SearchResult(
            id: "saved-\(barcode)", provenance: .openFoodFacts, name: name, caption: "",
            photo: nil, rank: rank,
            action: .choice(FoodChoice(
                source: .product(foodID: UUID()), name: name, perUnit: Nutrition(energy: 100),
                attribution: ProductAttribution(barcode: barcode, brand: nil, source: .openFoodFacts)
            ))
        )
    }

    @Test func bestMatchFirstWhateverTheSource() {
        let merged = SearchResults.merged(
            local: [result("Mine", .yours, rank: 0.4)],
            database: [result("Measured", .database, rank: 0.9)],
            products: [result("Branded", .openFoodFacts, rank: 0.6, barcode: "1")]
        )
        #expect(merged.map(\.name) == ["Measured", "Branded", "Mine"])
    }

    @Test func tiesKeepTheOrderTheyWereMergedIn() {
        let merged = SearchResults.merged(
            local: [result("A", .yours, rank: 0.5), result("B", .recipe, rank: 0.5)],
            database: [result("C", .database, rank: 0.5)],
            products: [result("D", .openFoodFacts, rank: 0.5, barcode: "1")]
        )
        #expect(merged.map(\.name) == ["A", "B", "C", "D"])
    }

    @Test func aProductAlreadySavedIsNotOfferedTwice() {
        let merged = SearchResults.merged(
            local: [saved("Kinder Bueno", barcode: "8000500037560", rank: 0.9)],
            database: [],
            products: [
                result("Kinder Bueno", .openFoodFacts, rank: 0.95, barcode: "8000500037560"),
                result("Kinder Bueno Coconut", .openFoodFacts, rank: 0.8, barcode: "80960270"),
            ]
        )
        #expect(merged.map(\.name) == ["Kinder Bueno", "Kinder Bueno Coconut"])
        // The saved copy is the one that survives, because it knows the last amount.
        #expect(merged.first?.barcode == "8000500037560")
        if case .choice = merged.first?.action {} else {
            Issue.record("the saved copy should be the one kept")
        }
    }

    @Test func pillsNameTheSource() {
        #expect(SearchResult.Provenance.recipe.pill == "Recipe")
        #expect(SearchResult.Provenance.yours.pill == "Yours")
        #expect(SearchResult.Provenance.database.pill == "Database")
        #expect(SearchResult.Provenance.openFoodFacts.pill == "Open Food Facts")
    }
}
