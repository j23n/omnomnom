import Foundation
import Testing
@testable import Omnomnom

/// Editing maths behind the draft screen: what a row is worth, what blocks logging,
/// the totals, and the banner.
struct EstimateDraftTests {
    private let eggs = FoodChoice(
        source: .bundled(id: 1), name: "Eggs, scrambled, cooked", perUnit: Nutrition(energy: 149, protein: 10, sodium: 145)
    )
    private let bread = FoodChoice(
        source: .bundled(id: 2), name: "Bread, rye", perUnit: Nutrition(energy: 260, carbohydrates: 48)
    )

    private func item(_ name: String, grams: Double, choice: FoodChoice?) -> ResolvedEstimateItem {
        ResolvedEstimateItem(name: name, grams: grams, choice: choice)
    }

    private func draft(_ items: [ResolvedEstimateItem], note: String = "Guessed.") -> EstimateDraft {
        EstimateDraft(note: note, items: items)
    }

    @Test func rowsPrefillFromTheItemsAndTakeTheirValuesFromTheMatch() {
        let items = [item("Scrambled eggs", grams: 100, choice: eggs), item("Rye toast", grams: 50, choice: bread)]
        let draft = draft(items)
        #expect(draft.rows.count == 2)
        #expect(draft.rows[0].name == "Scrambled eggs")
        #expect(draft.rows[0].amountText == "100")
        #expect(draft.rows[0].measure == .mass)
        #expect(draft.rows[0].choice == eggs)
        #expect(draft.rows[0].nutrition == Nutrition(energy: 149, protein: 10, sodium: 145))
        #expect(draft.hasUnmatchedRows == false)
        #expect(draft.items == items)
        #expect(draft.totals.energy == 279)
        #expect(draft.totals.fiber == 0)
    }

    @Test func aRowWithoutAFoodBlocksLoggingAndCountsForNothing() {
        var draft = draft([item("Scrambled eggs", grams: 100, choice: eggs), item("Sauce", grams: 30, choice: nil)])
        #expect(draft.hasUnmatchedRows)
        #expect(draft.rows[1].item == nil)
        #expect(draft.rows[1].nutrition == nil)
        #expect(draft.items == nil)
        #expect(draft.totals.energy == 149)
        draft.rows[1].choice = bread
        #expect(draft.hasUnmatchedRows == false)
        #expect(draft.items?.count == 2)
        #expect(draft.totals.energy == 149 + 78)
    }

    @Test func theAmountMustParseAndStayInRange() {
        var draft = draft([item("Scrambled eggs", grams: 100, choice: eggs)])
        draft.rows[0].amountText = "0"
        #expect(draft.rows[0].isAmountInvalid)
        #expect(draft.items == nil)
        #expect(draft.totals == Nutrition.zero)
        draft.rows[0].amountText = "62,5"
        #expect(draft.rows[0].isAmountInvalid == false)
        #expect(draft.items?[0].grams == 62.5)
    }

    /// Picking a food measured by volume makes the row's number millilitres; the values
    /// still come from that food, scaled by the number as typed.
    @Test func aVolumeFoodMakesTheRowsNumberMillilitres() {
        let oatDrink = FoodChoice(
            source: .custom(foodID: UUID()), name: "Oat drink",
            perUnit: Nutrition(energy: 46), measure: .volume
        )
        var draft = draft([item("Latte", grams: 250, choice: eggs)])
        draft.rows[0].choice = oatDrink
        #expect(draft.rows[0].measure == .volume)
        #expect(draft.rows[0].amount == 250)
        #expect(draft.totals.energy == 115)
    }

    @Test func removingRowsAndAnEmptyDraft() {
        let items = [item("Scrambled eggs", grams: 100, choice: eggs), item("Rye toast", grams: 50, choice: bread)]
        var draft = draft(items)
        draft.remove(id: items[0].id)
        #expect(draft.rows.map(\.name) == ["Rye toast"])
        draft.remove(id: items[1].id)
        #expect(draft.items == nil)
        #expect(draft.hasUnmatchedRows == false)
        #expect(draft.totals == Nutrition.zero)
    }

    @Test func outcomeFoldsProblemsIntoOneBanner() {
        let fine = LogResult(entryID: UUID(), written: [.energy], healthError: nil, storeError: nil)
        let denied = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil)
        #expect(EstimationLogOutcome(results: [fine]).bannerMessage == "Logged 1 estimated item.")
        #expect(EstimationLogOutcome(results: [fine, fine]).bannerMessage == "Logged 2 estimated items.")
        let mixed = EstimationLogOutcome(results: [fine, denied, denied]).bannerMessage
        #expect(mixed == "Logged 3 estimated items. Logged here only. Health didn't accept it.")
    }

    @Test func outcomeSaysWhatCouldNotBeLoggedOrKept() {
        let fine = LogResult(entryID: UUID(), written: [.energy], healthError: nil, storeError: nil)
        let partial = EstimationLogOutcome(results: [fine, fine], loggedRowIDs: [UUID(), UUID()], failed: ["Rye toast"])
        #expect(partial.bannerMessage == "Logged 2 estimated items. 1 item could not be logged.")
        let worse = EstimationLogOutcome(results: [fine], failed: ["Rye toast", "Butter"], photoFailed: true)
        #expect(worse.bannerMessage == "Logged 1 estimated item. 2 items could not be logged. The photo could not be kept.")
    }
}
