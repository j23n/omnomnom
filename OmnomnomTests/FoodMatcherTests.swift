import Foundation
import Testing
@testable import Omnomnom

/// Whether a row deserves to be logged without anyone looking at it.
///
/// The expected scores here were settled by running the same arithmetic over real
/// Ciqual and BLS names rather than by choosing numbers that felt right, which is what
/// the thresholds have to answer to. The cases that matter are the ones where a text
/// search is confidently wrong: "coffee" finding the powder, "chicken" finding the raw
/// row, "milk" finding the dried one.
struct FoodMatcherTests {
    private func food(
        _ name: String,
        id: Int = 1,
        alt: [String] = [],
        popularity: Int = 0,
        ingredient: Bool = false
    ) -> BundledFood {
        BundledFood(
            id: id,
            name: name,
            category: nil,
            per100g: Nutrition(energy: 100),
            popularity: popularity,
            altNames: alt,
            isIngredient: ingredient
        )
    }

    // MARK: - The failure this exists to stop

    @Test func brewedCoffeeSettlesAndThePowderNeverDoes() {
        let brewed = food("Coffee, beverage, brewed", id: 1)
        let powder = food("Coffee, instant, powder", id: 2, ingredient: true)
        let shortlist = FoodMatcher.shortlist([powder, brewed], term: "coffee")

        // The drink comes first even though the powder is just as good a text match.
        #expect(shortlist.first?.food == brewed)
        #expect(shortlist.first?.confidence == .settled)
        // And the powder cannot be logged by itself at any score.
        #expect(FoodMatcher.best([powder], term: "coffee")?.confidence == .unsure)
    }

    @Test func anIngredientFormIsNeverBetterThanUnsure() {
        // Even an exact match on the name it carries.
        let salt = food("Salt", ingredient: true)
        let match = FoodMatcher.best([salt], term: "salt")
        #expect(match?.score ?? 0 > 0)
        #expect(match?.confidence == .unsure)
    }

    @Test func rawMeatLosesToCookedMeat() {
        let grilled = food("Chicken breast, grilled", id: 1)
        let raw = food("Chicken, breast, raw", id: 2, ingredient: true)
        let shortlist = FoodMatcher.shortlist([raw, grilled], term: "chicken")
        #expect(shortlist.first?.food == grilled)
        #expect(shortlist.last?.food == raw)
    }

    @Test func driedMilkLosesToMilk() {
        let whole = food("Milk, whole, 3.5% fat", id: 1)
        let dried = food("Milk, dried, skimmed", id: 2, ingredient: true)
        #expect(FoodMatcher.shortlist([dried, whole], term: "milk").first?.food == whole)
    }

    @Test func thePenaltyExceedsEveryGapBetweenTiers() {
        // Why the penalty is large: it has to beat the distance between any two match
        // tiers, or a powder that matches better than the drink would still win.
        let gaps = [
            SearchRelevance.exact - SearchRelevance.prefix,
            SearchRelevance.prefix - SearchRelevance.wordPrefix,
            SearchRelevance.wordPrefix - SearchRelevance.substring,
            SearchRelevance.substring - SearchRelevance.everyToken,
        ]
        for gap in gaps {
            #expect(FoodMatcher.ingredientPenalty > gap)
        }
    }

    // MARK: - Scoring in a language the row does not display

    @Test func aFrenchQueryReachesARowThatReadsInEnglish() {
        // Ciqual rows display English and are found by their French name. Scoring only
        // the display name would refuse to match in any language but the one on screen.
        let withAlt = food("Apple, pulp and skin, raw", alt: ["Pomme, pulpe et peau, crue"])
        let withoutAlt = food("Apple, pulp and skin, raw")
        #expect(FoodMatcher.score(withAlt, term: "pomme") > FoodMatcher.settledAt)
        #expect(FoodMatcher.score(withoutAlt, term: "pomme") == 0)
    }

    @Test func aGermanNameOnTheAltListScoresExactly() {
        let oats = food("Oats, rolled", alt: ["Haferflocken"])
        #expect(FoodMatcher.score(oats, term: "haferflocken") == 1)
    }

    // MARK: - Ordinary foods settle

    @Test func plainFoodsAreLoggedWithoutAsking() {
        for name in ["Oats, rolled", "Banana, raw", "Peanut butter, smooth"] {
            let term = String(name.prefix(while: { $0 != "," }))
            #expect(FoodMatcher.best([food(name)], term: term)?.confidence == .settled)
        }
    }

    @Test func aWeakMatchIsOfferedRatherThanDiscarded() {
        // "oat" finds oat biscuits as a word prefix. It is not settled, and it is also
        // not thrown away: showing the row the user can correct beats showing nothing.
        let biscuits = food("Biscuits, oat")
        let match = FoodMatcher.best([biscuits], term: "oat")
        #expect(match != nil)
        #expect(match?.confidence == .probable)
    }

    @Test func nothingInCommonMatchesNothingAtAll() {
        #expect(FoodMatcher.best([food("Banana, raw")], term: "cement") == nil)
        #expect(FoodMatcher.shortlist([food("Banana, raw")], term: "cement").isEmpty)
    }

    @Test func aBlankTermMatchesNothing() {
        #expect(FoodMatcher.best([food("Banana, raw")], term: "   ") == nil)
    }

    // MARK: - The prior, and determinism

    @Test func popularityBreaksATieAndNoMore() {
        let plain = food("Rice, cooked", id: 1)
        let popular = food("Rice, cooked", id: 2, popularity: 9)
        #expect(FoodMatcher.score(popular, term: "rice") > FoodMatcher.score(plain, term: "rice"))
        // Capped, so a prior can never carry a poor match over a good one.
        let difference = FoodMatcher.score(popular, term: "rice") - FoodMatcher.score(plain, term: "rice")
        #expect(difference <= FoodMatcher.popularityCeiling)
    }

    @Test func tiesBreakByIDSoOneTermAlwaysResolvesTheSameWay() {
        let candidates = [food("Rice, cooked", id: 7), food("Rice, cooked", id: 3)]
        #expect(FoodMatcher.shortlist(candidates, term: "rice").map(\.food.id) == [3, 7])
        #expect(FoodMatcher.shortlist(candidates.reversed(), term: "rice").map(\.food.id) == [3, 7])
    }

    @Test func theShortlistHonoursItsLimit() {
        let candidates = (1...20).map { food("Rice, type \($0)", id: $0) }
        #expect(FoodMatcher.shortlist(candidates, term: "rice").count == 8)
        #expect(FoodMatcher.shortlist(candidates, term: "rice", limit: 3).count == 3)
    }

    @Test func scoresStayInRange() {
        let extreme = food("Rice", popularity: 10_000)
        #expect(FoodMatcher.score(extreme, term: "rice") <= 1)
        let penalised = food("Oil", ingredient: true)
        #expect(FoodMatcher.score(penalised, term: "oil") >= 0)
    }

    @Test func thresholdsAreOrdered() {
        #expect(FoodMatcher.settledAt > FoodMatcher.probableAt)
        #expect(FoodMatcher.probableAt > 0)
        #expect(FoodMatcher.settledAt < 1)
    }
}
