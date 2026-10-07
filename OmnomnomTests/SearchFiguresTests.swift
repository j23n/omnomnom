import Foundation
import Testing
@testable import Omnomnom

/// The pill that tells two otherwise identical rows apart.
struct SearchFiguresTests {
    private let whole = Nutrition(
        energy: 264, protein: 14, carbohydrates: 4, fatTotal: 21,
        fatSaturated: 15, fiber: 0, sugar: 4, sodium: 1_116
    )

    @Test func aCompleteRowSaysSo() {
        let figures = SearchResult.Figures(of: whole)
        #expect(figures.isComplete)
        #expect(figures.pill == "All 8")
        #expect(figures.spoken == "Every nutrient figure")
    }

    @Test func zeroIsAFigureAndNotAGap() {
        // Feta holds no fibre, and the table says so with a 0 rather than a blank. A row
        // that measured something as absent is a complete row.
        #expect(whole.fiber == 0)
        #expect(SearchResult.Figures(of: whole).isComplete)
    }

    @Test func oneGapIsNamedBecauseWhichFigureIsMissingIsWhatDecides() {
        // Someone watching sodium cares about a different absence than someone watching
        // fibre, so the one case that fits names itself.
        var short = whole
        short.fiber = nil
        let figures = SearchResult.Figures(of: short)
        #expect(!figures.isComplete)
        #expect(figures.pill == "No fiber figure")
        #expect(figures.spoken == "No figure for fiber")
    }

    @Test func pastOneTheCountIsWhatFits() {
        var short = whole
        short.fiber = nil
        short.sugar = nil
        short.sodium = nil
        let figures = SearchResult.Figures(of: short)
        #expect(figures.pill == "3 figures missing")
        #expect(figures.spoken.hasPrefix("Missing 3 nutrient figures: "))
        // Named in the nutrients' own order, never in order of how much is missing, which
        // would be a judgement about which gap matters.
        let names = ["fiber", "sugar", "sodium"].map { figures.spoken.range(of: $0)?.lowerBound }
        #expect(names.allSatisfy { $0 != nil })
        #expect(names.compactMap { $0 } == names.compactMap { $0 }.sorted())
    }

    @Test func aRowWithNothingAtAllIsEightShort() {
        let figures = SearchResult.Figures(of: .empty)
        #expect(figures.missing.count == Nutrient.allCases.count)
        #expect(figures.pill == "8 figures missing")
    }

    @Test func nothingInThePillIsAVerdict() {
        // A row short of a figure is often the right answer anyway — a brand that declares
        // only what a label must declare is still that brand — so the pill counts and
        // never grades.
        var short = whole
        short.sodium = nil
        for figures in [SearchResult.Figures(of: whole), SearchResult.Figures(of: short)] {
            for word in ["%", "incomplete", "poor", "better", "worse", "bad", "good"] {
                #expect(!figures.pill.lowercased().contains(word))
                #expect(!figures.spoken.lowercased().contains(word))
            }
        }
    }

    // MARK: - Where it comes from

    @Test func aBundledRowIsReadFromItsOwnTable() {
        let feta = BundledFood(
            id: 1, name: "Feta", category: "Cheese", per100g: whole,
            popularity: 0, altNames: [], isIngredient: false
        )
        #expect(SearchResult.make(bundled: feta, query: "feta").figures.isComplete)
        var short = whole
        short.fiber = nil
        let unmeasured = BundledFood(
            id: 2, name: "Feta", category: "Cheese", per100g: short,
            popularity: 0, altNames: [], isIngredient: false
        )
        #expect(SearchResult.make(bundled: unmeasured, query: "feta").figures.pill == "No fiber figure")
    }

    @Test func aProductIsReadFromWhatTheIndexHeld() {
        // The case this exists for: a crowdsourced record with an energy figure and
        // nothing else, which looks identical to a measured row until the pill.
        let record = ProductRecord(
            code: "1", name: "Oat drink", brand: "Oatly", per100g: Nutrition(energy: 46)
        )
        let result = SearchResult.make(product: record, query: "oat drink")
        #expect(!result.figures.isComplete)
        #expect(result.figures.missing.count == 7)
    }

    // MARK: - What a missing figure means to the rest of the app

    @Test func nutritionKnowsWhatItIsShortOf() {
        var short = whole
        short.fiber = nil
        #expect(short.missingNutrients == [.fiber])
        #expect(!short.isComplete)
        #expect(whole.isComplete)
        #expect(Nutrition.empty.missingNutrients == Set(Nutrient.allCases))
    }
}
