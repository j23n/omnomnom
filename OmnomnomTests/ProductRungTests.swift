import Foundation
import Testing
@testable import Omnomnom

/// The bar a product has to clear to answer for a food the bundled tables do not hold.
///
/// The search index matches more than this app asks it to — categories, labels, text it
/// never requested — so it answers a narrow term with a wide list. These are about what is
/// then thrown away, which is the only part of the rung that can be tested without a
/// network.
struct ProductRungTests {
    private func record(_ name: String, brand: String? = nil, code: String = "1") -> ProductRecord {
        ProductRecord(code: code, name: name, brand: brand, per100g: Nutrition(energy: 600))
    }

    @Test func theProductNamingTheFoodWins() {
        let best = ProductRung.bestMatch(for: "peanut butter", in: [
            record("Peanut butter", code: "a"),
            record("Peanut butter cups", code: "b"),
            record("Chocolate spread", code: "c"),
        ])
        #expect(best?.code == "a")
    }

    /// A brand is part of what a product can be found by, as it is in the search list.
    @Test func aBrandCountsAsTheName() {
        let best = ProductRung.bestMatch(for: "nutella", in: [
            record("Hazelnut spread", brand: "Nutella", code: "a"),
            record("Chocolate biscuits", brand: "Ferrero", code: "b"),
        ])
        #expect(best?.code == "a")
    }

    /// The case the bar exists for: the index answers, nothing it answered is the food, and
    /// a row with no food that the user settles is better than a confident wrong one.
    @Test func aTangentialHitIsNotAnAnswer() {
        let best = ProductRung.bestMatch(for: "peanut butter", in: [
            record("Chocolate spread"),
            record("Salted crackers"),
        ])
        #expect(best == nil)
    }

    @Test func nothingFoundIsNothingChosen() {
        #expect(ProductRung.bestMatch(for: "peanut butter", in: []) == nil)
    }

    /// Every word present is the bar, which is the rule the bundled index applies by
    /// construction: its query ands a term's words together.
    @Test func halfOfTheTermIsNotEnough() {
        let best = ProductRung.bestMatch(for: "oat milk", in: [record("Whole milk")])
        #expect(best == nil)
    }

    @Test func theFloorSitsBelowAMatchAndAboveNoMatch() {
        // What a row scores when a source returned it for a reason this app cannot see.
        let unexplained = SearchRelevance.unexplained + SearchRelevance.bonus(isCrowdsourced: true)
        #expect(ProductRung.floor > unexplained)
        #expect(ProductRung.floor < SearchRelevance.everyToken)
    }
}
