import Foundation
import Testing
@testable import Omnomnom

/// What the sign-off screen's three edits do to the line under it. The screen itself
/// holds nothing: every change goes through the model, so the rows the Log button reads
/// are the rows the user left behind.
struct ComposerModelTests {
    private func choice(_ name: String, kcal: Double = 100) -> FoodChoice {
        FoodChoice(
            source: .bundled(id: abs(name.hashValue % 10_000)),
            name: name,
            perUnit: Nutrition(energy: kcal)
        )
    }

    private func row(_ name: String, amount: Double = 100, origin: RowOrigin = .database) -> ResolvedRow {
        ResolvedRow(
            name: name, choice: choice(name), amount: amount,
            origin: origin, confidence: .settled
        )
    }

    private func composer(rows: [ResolvedRow]) -> ComposerModel {
        let model = ComposerModel()
        model.resolution = LineResolution(line: "oats", rows: rows, wasChecked: false)
        return model
    }

    @Test func addedFoodJoinsTheSameLine() {
        let model = composer(rows: [row("Oat flakes", amount: 40)])
        model.add(row("Coffee", amount: 200, origin: .chosen))
        #expect(model.resolution?.rows.count == 2)
        #expect(model.resolution?.rows.last?.displayName == "Coffee")
        // The screen reads its energy off the whole line, so the second food has to
        // count towards it rather than only towards itself.
        #expect(model.resolution?.total.energy == 240)
    }

    /// The order is what the user watches grow. A food added last belongs last, not
    /// sorted into some ranking they never asked for.
    @Test func addedFoodGoesOnTheEnd() {
        let model = composer(rows: [row("Oat flakes"), row("Banana")])
        model.add(row("Coffee", origin: .chosen))
        #expect(model.resolution?.rows.map(\.displayName) == ["Oat flakes", "Banana", "Coffee"])
    }

    /// Nothing to add to. The picker cannot be open without a line behind it, so this is
    /// only the guarantee that a late callback cannot conjure a resolution back onto the
    /// screen after the line was logged or abandoned.
    @Test func addingWithoutALineDoesNothing() {
        let model = ComposerModel()
        model.add(row("Coffee", origin: .chosen))
        #expect(model.resolution == nil)
    }

    @Test func changingARowKeepsItsPlace() {
        let model = composer(rows: [row("Oat flakes"), row("Banana")])
        var edited = model.resolution?.rows[0] ?? row("Oat flakes")
        edited.amount = 60
        model.update(edited)
        #expect(model.resolution?.rows.map(\.displayName) == ["Oat flakes", "Banana"])
        #expect(model.resolution?.rows[0].amount == 60)
    }

    /// Removing the last row closes the screen, which is what a `nil` resolution means:
    /// a line with nothing on it has nothing to sign off.
    @Test func removingTheLastRowEndsTheLine() {
        let only = row("Oat flakes")
        let model = composer(rows: [only])
        model.remove(only)
        #expect(model.resolution == nil)
    }
}
