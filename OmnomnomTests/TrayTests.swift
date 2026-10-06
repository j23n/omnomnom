import Foundation
import Testing
@testable import Omnomnom

/// The tray: what its bar says, and the row edits its screen makes.
struct TrayTests {
    private func row(_ name: String, kcal: Double?, amount: Double) -> ResolvedRow {
        ResolvedRow(
            name: name,
            choice: FoodChoice(
                source: .bundled(id: abs(name.hashValue % 10_000)),
                name: name,
                perUnit: Nutrition(energy: kcal)
            ),
            amount: amount,
            origin: .chosen,
            confidence: .settled
        )
    }

    private func tray(_ rows: [ResolvedRow]) -> LineResolution {
        LineResolution(line: "", rows: rows, wasChecked: false)
    }

    // MARK: - What the bar says

    @Test func oneFoodIsNamedRatherThanCounted() {
        // "1 food · 167 kcal" says less than the food's own name does.
        #expect(TrayBar.title(tray([row("Oat flakes", kcal: 372, amount: 45)])) == "Oat flakes · 167 kcal")
    }

    @Test func severalFoodsAreCountedAndTotalled() {
        let gathered = tray([
            row("Oat flakes", kcal: 372, amount: 45),
            row("Banana", kcal: 89, amount: 120),
            row("Milk", kcal: 47, amount: 200)
        ])
        #expect(TrayBar.title(gathered) == "3 foods · 368 kcal")
    }

    @Test func aFoodWithNoEnergyFigureIsStillNamed() {
        // No total rather than a total of nothing: a figure the tables do not hold is not
        // zero, and a bar reading "0 kcal" would be a claim about the food.
        #expect(TrayBar.title(tray([row("Chewing gum", kcal: nil, amount: 3)])) == "Chewing gum")
    }

    // MARK: - Editing what is in it

    @Test func anEditedRowGoesBackWhereItWas() {
        var gathered = tray([row("Oat flakes", kcal: 372, amount: 45), row("Banana", kcal: 89, amount: 120)])
        var edited = gathered.rows[0]
        edited.amount = 60
        gathered.replace(edited)
        #expect(gathered.rows.map(\.displayName) == ["Oat flakes", "Banana"])
        #expect(gathered.rows[0].amount == 60)
    }

    @Test func aRowFromAScreenLeftBehindIsNotAppended() {
        // The guarantee that a late callback cannot put a food back into a meal the user
        // has moved on from.
        var gathered = tray([row("Oat flakes", kcal: 372, amount: 45)])
        gathered.replace(row("Banana", kcal: 89, amount: 120))
        #expect(gathered.rows.count == 1)
        #expect(gathered.rows[0].displayName == "Oat flakes")
    }

    @Test func anAddedFoodGoesOnTheEnd() {
        var gathered = tray([row("Oat flakes", kcal: 372, amount: 45)])
        gathered.append(row("Coffee", kcal: 2, amount: 250))
        #expect(gathered.rows.map(\.displayName) == ["Oat flakes", "Coffee"])
    }

    @Test func removingTakesOnlyThatRow() {
        var gathered = tray([row("Oat flakes", kcal: 372, amount: 45), row("Banana", kcal: 89, amount: 120)])
        gathered.remove(gathered.rows[0])
        #expect(gathered.rows.map(\.displayName) == ["Banana"])
    }

    // MARK: - What a tray teaches

    @Test func aTrayIsNotALineAndSoTeachesNothing() {
        // A phrase is remembered under a key made from the line that was typed. Nobody
        // typed anything here, and `remember` wants a key it can normalise from one.
        #expect(PhraseKey.normalise(tray([row("Oat flakes", kcal: 372, amount: 45)]).line) == nil)
    }

    @Test func everythingGatheredIsLoggable() {
        // Nothing in a tray was guessed, so nothing in it blocks or carries a mark.
        let gathered = tray([row("Oat flakes", kcal: 372, amount: 45), row("Banana", kcal: 89, amount: 120)])
        #expect(gathered.canLog)
        #expect(gathered.glanceCount == 0)
        #expect(gathered.blockingCount == 0)
        #expect(gathered.rows.allSatisfy(\.isSettled))
    }
}
