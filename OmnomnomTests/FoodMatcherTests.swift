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

    @Test func aGermanNameOnTheAltListScoresAsAnExactMatch() {
        let oats = food("Oats, rolled", alt: ["Haferflocken"])
        // Exact plus full coverage, and no longer clamped: see `SearchRelevance.score`.
        #expect(FoodMatcher.score(oats, term: "haferflocken") == SearchRelevance.exact + SearchRelevance.coverageWeight)
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

    @Test func scoresHaveAFloorAndNoCeiling() {
        // No upper clamp. A clamp made every strong match identical, so "Apple raw" and
        // "Apple juice" both reached 1 and the tie fell to whichever had the lower id.
        // Thresholds read the same either way and ordering needs the headroom.
        let extreme = food("Rice", popularity: 10_000)
        #expect(FoodMatcher.score(extreme, term: "rice") > 1)
        // A penalty can never take a score below nothing.
        let penalised = food("Oil", ingredient: true)
        #expect(FoodMatcher.score(penalised, term: "oil") >= 0)
    }

    @Test func thePriorIsMostlyAboutMembershipNotPosition() {
        // Every row on the curated list is there because it is *the* form someone means
        // by a bare noun, so being on it matters far more than where. Scaling by position
        // left the fortieth entry unable to beat a derivative, and "cheese" went on
        // returning a cheeseburger.
        #expect(FoodMatcher.prior(for: 0) == 0)
        #expect(FoodMatcher.prior(for: 1) >= FoodMatcher.popularityFloor)
        #expect(FoodMatcher.prior(for: 40) > SearchRelevance.prefix - SearchRelevance.wordPrefix)
        #expect(FoodMatcher.prior(for: 10_000) == FoodMatcher.popularityCeiling)
    }

    @Test func theScorerKnowsTheSamePluralsTheIndexDoes() {
        // A scorer that disagrees with the retriever about what a word is produces the
        // worst outcome there is: a row that is found and then scored at zero. "Oats"
        // against the German table's "Oat flakes" is exactly that case.
        let flakes = food("Oat flakes")
        #expect(FoodMatcher.score(flakes, term: "oats") > FoodMatcher.settledAt)
        #expect(FoodMatcher.score(flakes, term: "oat") > FoodMatcher.settledAt)
    }

    @Test func thresholdsAreOrdered() {
        #expect(FoodMatcher.settledAt > FoodMatcher.probableAt)
        #expect(FoodMatcher.probableAt > 0)
        #expect(FoodMatcher.settledAt < 1)
    }
}

/// What the matcher does against the names the real Bundeslebensmittelschlüssel uses.
///
/// Every case here failed when the matcher first met the real database: typing "oats"
/// found nothing at all, "coffee" returned ice cream, "milk" returned chocolate, "rice"
/// returned bran. Four separate causes, each fixed and each kept honest by one of these.
/// The rows are reproduced with the popularity the curated list gives them.
struct RealDatabaseMatchTests {
    private func row(
        _ name: String, kcal: Double, popularity: Int = 0, ingredient: Bool = false, id: Int = 1
    ) -> BundledFood {
        BundledFood(
            id: id, name: name, category: nil, per100g: Nutrition(energy: kcal),
            popularity: popularity, altNames: [], isIngredient: ingredient
        )
    }

    private func winner(_ term: String, _ candidates: [BundledFood]) -> String? {
        FoodMatcher.best(candidates, term: term)?.food.name
    }

    @Test func oatsFindsTheFlakesAndNotWhateverContainsTheLetters() {
        // "Oat groats" used to win because "groats" contains "oats".
        let candidates = [
            row("Oat flakes", kcal: 348, popularity: 88, id: 1),
            row("Oat groats", kcal: 351, id: 2),
            row("Oat bran flakes", kcal: 371, id: 3),
        ]
        #expect(winner("oats", candidates) == "Oat flakes")
        #expect(winner("oat flakes", candidates) == "Oat flakes")
    }

    @Test func coffeeIsADrinkAndNotIceCream() {
        let candidates = [
            row("Coffee ice cream", kcal: 171, id: 1),
            row("Coffee (infusion)", kcal: 1, popularity: 100, id: 2),
            row("Coffee, instant, powder", kcal: 350, ingredient: true, id: 3),
        ]
        #expect(winner("coffee", candidates) == "Coffee (infusion)")
    }

    @Test func milkIsMilkAndNotMilkChocolate() {
        // The hardest of them: "Milk chocolate" genuinely takes the better text tier,
        // because it really does start with "milk". Only the prior separates them, which
        // is why it has to be worth more than the gap between two tiers.
        let candidates = [
            row("Milk chocolate", kcal: 532, id: 1),
            row("Whole milk, 3.5 % fat, ultra-heated", kcal: 62, popularity: 97, id: 2),
        ]
        #expect(winner("milk", candidates) == "Whole milk, 3.5 % fat, ultra-heated")
    }

    @Test func aCuratedEntryMustNeverBeTheWrongAnswerToABareNoun() {
        // "Milk chocolate" was on the curated list and so carried a prior of its own,
        // which put it back in front. It was removed for that reason.
        let candidates = [
            row("Milk chocolate", kcal: 532, popularity: 30, id: 1),
            row("Whole milk, 3.5 % fat, ultra-heated", kcal: 62, popularity: 97, id: 2),
        ]
        #expect(winner("milk", candidates) == "Milk chocolate")
    }

    @Test func aBareNounFindsTheFormPeopleEat() {
        let cases: [(String, [BundledFood], String)] = [
            ("chicken", [row("Chicken stock", kcal: 5, id: 1),
                         row("Chicken grilled", kcal: 257, popularity: 60, id: 2)], "Chicken grilled"),
            ("rice", [row("Rice bran", kcal: 380, id: 1),
                      row("Rice boiled", kcal: 112, popularity: 70, id: 2)], "Rice boiled"),
            ("egg", [row("Egg nog", kcal: 170, id: 1),
                     row("Eggs boiled", kcal: 135, popularity: 80, id: 2)], "Eggs boiled"),
            ("cheese", [row("Cheeseburger", kcal: 202, id: 1),
                        row("Gouda cheese 48 % fat in dry matter", kcal: 379, popularity: 40, id: 2)],
             "Gouda cheese 48 % fat in dry matter"),
            ("pasta", [row("Pasta egg-free, raw", kcal: 346, id: 1),
                       row("Egg pasta boiled", kcal: 130, popularity: 50, id: 2)], "Egg pasta boiled"),
        ]
        for (term, candidates, expected) in cases {
            #expect(winner(term, candidates) == expected, "\(term) should find \(expected)")
        }
    }

    @Test func aPluralFindsTheSingularRow() {
        let candidates = [row("Tomato raw", kcal: 22, popularity: 85), row("Tomato puree", kcal: 29, id: 2)]
        #expect(winner("tomatoes", candidates) == "Tomato raw")
        #expect(winner("tomato", candidates) == "Tomato raw")
    }
}
