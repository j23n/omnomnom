import Foundation
import os

extension EntryLogger {
    /// Accepts the match on a marked entry. The food was right, so the mark goes and
    /// nothing else changes.
    ///
    /// Nothing reaches Health: the values, the amount and the time are all exactly what
    /// was written, and the mark was never part of what was written. It is this app's
    /// record of a question it had, and this is the user answering it.
    func settle(_ entry: LogEntry) {
        guard entry.guessed else { return }
        entry.guessed = false
        saveQuietly("accept a match")
    }

    /// Swaps the food on an entry for one the user named, keeping the amount, the meal and
    /// the moment, and takes the mark off.
    ///
    /// Written as a delete and a fresh log rather than as an edit in place, because every
    /// kind of food — bundled, custom, product, recipe — reaches an entry through one path
    /// already, and a second path that rebuilt a snapshot from a choice would be the same
    /// code again with its own way of being wrong. The delete goes to Health first, so a
    /// correction never leaves two versions of a meal there; if Health will not release the
    /// old samples nothing is logged, and the row stays as it was.
    ///
    /// What the line said is carried over, and so is how the entry came to exist: it was
    /// still typed, and a day's coverage must not change because one row was corrected.
    func replaceFood(of entry: LogEntry, with choice: FoodChoice) async -> String {
        let amount = Self.amount(replacing: entry, with: choice)
        let slot = entry.mealSlot
        let timestamp = entry.timestamp
        let origin = entry.origin
        let wording = entry.wording
        let previous = entry.foodName
        let photo = entry.photo

        switch await delete(entry) {
        case .deleted:
            break
        case .orphaned:
            return "Health is still holding \(previous), so nothing was changed."
        case .failed(let why):
            return "Could not change \(previous): \(why)"
        }

        do {
            let result = try await log(choice: choice, amount: amount, mealSlot: slot, at: timestamp)
            if let fresh = entry(id: result.entryID) {
                fresh.origin = origin
                fresh.wording = wording
                fresh.guessed = false
                // Only where it outlived the row it came from, which it does when another
                // entry of the same plate still refers to it.
                if let photo, !photo.isDeleted {
                    fresh.photo = photo
                }
                saveQuietly("record the food you chose")
            }
            return result.bannerMessage ?? "\(choice.name) instead of \(previous)."
        } catch {
            AppLog.store.error("could not log the chosen food: \(error.localizedDescription, privacy: .public)")
            return "\(previous) was removed, but \(choice.name) could not be logged."
        }
    }

    /// How much of the new food to log.
    ///
    /// The number the user was looking at, read as the new food's own unit: a row saying
    /// 200 of something stays 200 of what it turned out to be. That is the whole of it for
    /// a food, because the figure on the row is already in the food's own unit and the two
    /// units a food can have — grams and millilitres — are the same number of the same
    /// stuff to within the difference this app has any opinion about.
    ///
    /// Servings are the exception in both directions. A serving of one recipe is not a
    /// serving of another and is certainly not 200 of anything, so a recipe at either end
    /// falls back to what this person last had of it, or to one serving.
    static func amount(replacing entry: LogEntry, with choice: FoodChoice) -> Double {
        if choice.isRecipe {
            return choice.lastAmount ?? 1
        }
        if entry.servings != nil {
            return choice.lastAmount ?? Self.defaultAmount
        }
        let logged = entry.rawAmount.amount(in: entry.measure)
        return logged > 0 ? logged : (choice.lastAmount ?? Self.defaultAmount)
    }

    /// What a food with no history behind it starts at. The draft screens each keep their
    /// own; this is the logger's, for the correction that has no number to read off the row.
    static let defaultAmount = 100.0
}
