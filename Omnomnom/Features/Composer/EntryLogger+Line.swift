import Foundation
import os
import SwiftData

/// What logging a whole line came to.
nonisolated struct LineLogOutcome: Sendable {
    /// One result per row that reached Health, in the order of the line.
    let results: [LogResult]
    /// Rows that could not be logged because what they pointed at had gone.
    let failed: Int
    /// Whether the line was remembered, which it is not when it has no key.
    let remembered: Bool

    var loggedCount: Int { results.count }
}

extension EntryLogger {
    /// Logs every row of a resolved line, then remembers what the line resolved to.
    ///
    /// Rows are logged one after another through the same path the Quantity sheet uses,
    /// so there is one way a food reaches Health and not two. A row that cannot be logged
    /// is counted and skipped rather than failing the line: four foods of five in the log
    /// beats none of them.
    ///
    /// The phrase is written last and only from rows that actually logged, so a memory
    /// never promises a food that was not recorded. It is written even when some rows
    /// failed, because what succeeded is still the best reading of that line.
    @discardableResult
    func logLine(
        _ resolution: LineResolution,
        mealSlot: MealSlot,
        at timestamp: Date,
        origin: EntryOrigin = .typed
    ) async -> LineLogOutcome {
        var results: [LogResult] = []
        var drafts: [PhraseDraftItem] = []
        var failed = 0

        for row in resolution.rows {
            guard let choice = row.choice else {
                failed += 1
                continue
            }
            do {
                let result = try await log(
                    choice: choice, amount: row.amount, mealSlot: mealSlot, at: timestamp
                )
                results.append(result)
                markOrigin(result.entryID, as: origin)
                drafts.append(draft(for: row, choice: choice))
            } catch {
                failed += 1
                AppLog.store.error("row not logged: \(error.localizedDescription, privacy: .public)")
            }
        }

        var remembered = false
        if !drafts.isEmpty {
            do {
                remembered = try Phrase.remember(
                    line: resolution.line, items: drafts, in: context
                ) != nil
                try context.save()
            } catch {
                AppLog.store.error("line not remembered: \(error.localizedDescription, privacy: .public)")
            }
        }
        AppLog.store.info("logged \(results.count) of \(resolution.rows.count) rows from one line")
        return LineLogOutcome(results: results, failed: failed, remembered: remembered)
    }

    /// Records how the entry came to exist. Saved with the phrase rather than on its own,
    /// since nothing reads it until the day is looked at.
    private func markOrigin(_ entryID: UUID, as origin: EntryOrigin) {
        let wanted: UUID = entryID
        var descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.id == wanted })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return }
        entry.origin = origin
    }

    /// What a logged row leaves in the memory: the food, and the amount it came to.
    ///
    /// The amount is kept rather than the bucket, because the bucket meant something
    /// only against the reference it was multiplied by. Next time this amount is itself
    /// the reference, which is what makes "usual" true.
    private func draft(for row: ResolvedRow, choice: FoodChoice) -> PhraseDraftItem {
        PhraseDraftItem(
            name: row.name,
            amount: row.amount,
            food: storedFood(for: choice),
            recipe: storedRecipe(for: choice)
        )
    }

    private func storedFood(for choice: FoodChoice) -> Food? {
        switch choice.source {
        case .bundled(let id): try? Food.bundled(id: id, in: context)
        case .custom(let foodID): try? Food.custom(id: foodID, in: context)
        case .product(let foodID): try? Food.product(id: foodID, in: context)
        case .recipe: nil
        }
    }

    private func storedRecipe(for choice: FoodChoice) -> Recipe? {
        guard case .recipe(let id) = choice.source else { return nil }
        return try? Recipe.find(id: id, in: context)
    }
}
