import Foundation
import SwiftData

/// One food inside a remembered phrase, with the amount that phrase resolved to.
///
/// The amount is in the food's own unit — grams or millilitres for a food, servings for
/// a recipe — exactly as `LogEntry.rawAmount` is, so recalling a phrase needs no
/// conversion and cannot introduce one.
///
/// Schema rules as elsewhere: no unique attributes, everything defaulted or optional,
/// relationships optional with their inverses declared on the other side, and its own
/// `sortIndex` rather than an ordered relationship, so a later CloudKit retrofit stays
/// a configuration change.
@Model
final class PhraseItem {
    var id: UUID = UUID()
    /// Position in the phrase, so the rows come back in the order they were logged.
    var sortIndex: Int = 0
    /// What this item was called when the phrase was last logged, for display before
    /// the food is read. The food's own name wins when there is one.
    var name: String = ""
    /// The amount in the food's own unit, or servings for a recipe.
    var amount: Double = 0
    var food: Food?
    var recipe: Recipe?
    var phrase: Phrase?

    init(sortIndex: Int, name: String, amount: Double) {
        self.id = UUID()
        self.sortIndex = sortIndex
        self.name = name
        self.amount = amount
    }

    /// Whether this item still points at something that can be logged. A food deleted
    /// from the Library leaves the item pointing at nothing, and a phrase holding such
    /// an item cannot be recalled whole.
    var isResolvable: Bool {
        food != nil || recipe != nil
    }
}
