import Foundation
import Testing
@testable import Omnomnom

/// Editing maths behind the draft screen: parsing, validity, totals, and the banner.
struct EstimateDraftTests {
    private let egg = EstimatedDraftItem(name: "Egg", grams: 50, nutrition: Nutrition(energy: 72, protein: 6.3, sodium: 71))
    private let toast = EstimatedDraftItem(name: "Toast", grams: 35, nutrition: Nutrition(energy: 90, carbohydrates: 17))

    private func draft(_ items: [EstimatedDraftItem], note: String = "Guessed.") -> EstimateDraft {
        EstimateDraft(result: EstimateConversion.Result(note: note, warnings: [], items: items))
    }

    @Test func rowsPrefillFromTheItemsAndRoundTrip() {
        let draft = draft([egg, toast])
        #expect(draft.rows.count == 2)
        #expect(draft.rows[0].name == "Egg")
        #expect(draft.rows[0].gramsText == "50")
        #expect(draft.rows[0].text(for: .protein) == "6.3")
        #expect(draft.rows[0].text(for: .fiber) == "")
        #expect(draft.items == [egg, toast])
        #expect(draft.totals.energy == 162)
        #expect(draft.totals.fiber == 0)
    }

    @Test func aBadFieldBlocksLoggingButNotTheTotals() {
        var draft = draft([egg, toast])
        draft.rows[1].setText("lots", for: .sugar)
        #expect(draft.rows[1].isInvalid(.sugar))
        #expect(draft.rows[1].item == nil)
        #expect(draft.items == nil)
        #expect(draft.totals.energy == 72)
        draft.rows[1].setText("1,5", for: .sugar)
        #expect(draft.items?[1].nutrition.sugar == 1.5)
    }

    @Test func gramsMustBeInRangeAndNameMustNotBeBlank() {
        var draft = draft([egg])
        draft.rows[0].gramsText = "0"
        #expect(draft.rows[0].isGramsInvalid)
        #expect(draft.items == nil)
        draft.rows[0].gramsText = "62,5"
        #expect(draft.items?[0].grams == 62.5)
        draft.rows[0].name = "  "
        #expect(draft.items == nil)
    }

    @Test func removingRowsAndAnEmptyDraft() {
        var draft = draft([egg, toast])
        draft.remove(id: egg.id)
        #expect(draft.rows.map(\.name) == ["Toast"])
        draft.remove(id: toast.id)
        #expect(draft.items == nil)
        #expect(draft.totals == Nutrition.zero)
    }

    @Test func outcomeFoldsProblemsIntoOneBanner() {
        let fine = LogResult(entryID: UUID(), written: [.energy], healthError: nil, storeError: nil)
        let denied = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil)
        #expect(EstimationLogOutcome(results: [fine]).bannerMessage == "Logged 1 estimated item.")
        #expect(EstimationLogOutcome(results: [fine, fine]).bannerMessage == "Logged 2 estimated items.")
        let mixed = EstimationLogOutcome(results: [fine, denied, denied]).bannerMessage
        #expect(mixed == "Logged 3 estimated items. Logged locally. Nothing reached Health; check Settings.")
    }
}
