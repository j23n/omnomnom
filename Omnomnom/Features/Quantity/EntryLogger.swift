import Foundation
import os
import SwiftData

/// Creates the local entry, then mirrors it to Health; deletes mirror to Health first.
/// Shared by the Quantity sheet and the swipe actions on Today. Main-actor because it
/// drives a `ModelContext`.
struct EntryLogger {
    let context: ModelContext
    let health: any HealthWriting

    /// Logs a bundled food picked in the Add sheet. The snapshot comes from the live
    /// choice; the stored `Food` copy is created on first use and refreshed if it drifted.
    func log(choice: FoodChoice, grams: Double, mealSlot: MealSlot, at timestamp: Date) async throws -> LogResult {
        let food: Food
        if let existing = try Food.bundled(id: choice.bundledID, in: context) {
            if existing.name != choice.name || existing.per100g != choice.per100g {
                existing.name = choice.name
                existing.per100g = choice.per100g
            }
            food = existing
        } else {
            food = Food(name: choice.name, kind: .bundled, bundledID: choice.bundledID, per100g: choice.per100g)
            context.insert(food)
        }
        return try await insert(name: choice.name, per100g: choice.per100g, food: food, grams: grams, mealSlot: mealSlot, at: timestamp)
    }

    /// Re-logs a stored food, as the repeat action does.
    func log(food: Food, grams: Double, mealSlot: MealSlot, at timestamp: Date) async throws -> LogResult {
        try await insert(name: food.name, per100g: food.per100g, food: food, grams: grams, mealSlot: mealSlot, at: timestamp)
    }

    /// Mirrors the delete to Health, then removes the entry locally. Never throws: the
    /// outcome says what happened and the row is left in place unless both steps passed.
    /// An entry already flagged `orphaned` skips Health, so a second delete removes it here.
    func delete(_ entry: LogEntry) async -> DeleteOutcome {
        let written = entry.written
        if !written.isEmpty, !entry.orphaned {
            do {
                try await health.delete(entryID: entry.id, nutrients: written)
            } catch HealthWriteError.authorizationDenied {
                entry.orphaned = true
                saveQuietly("flag orphaned")
                return .orphaned
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        context.delete(entry)
        do {
            try context.save()
        } catch {
            AppLog.store.error("local delete failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        return .deleted
    }

    /// The local save is the part that throws; Health and the follow-up save report through the result.
    private func insert(name: String, per100g: Nutrition, food: Food, grams: Double, mealSlot: MealSlot, at timestamp: Date) async throws -> LogResult {
        let entry = LogEntry(
            timestamp: timestamp,
            mealSlot: mealSlot,
            foodName: name,
            grams: grams,
            snapshot: SnapshotMath.snapshot(per100g: per100g, grams: grams)
        )
        context.insert(entry)
        entry.food = food
        food.noteUsed(grams: grams, at: Date.now)
        try context.save()
        AppLog.store.info("logged \(entry.id.uuidString, privacy: .public)")
        return await mirror(entry)
    }

    private func mirror(_ entry: LogEntry) async -> LogResult {
        let request = HealthWriteRequest(
            entryID: entry.id,
            foodName: entry.foodName,
            mealSlot: entry.mealSlot,
            start: entry.timestamp,
            nutrition: entry.snapshot,
            syncVersion: entry.syncVersion
        )
        let written: Set<Nutrient>
        do {
            written = try await health.write(request)
        } catch {
            AppLog.health.error("health write failed: \(error.localizedDescription, privacy: .public)")
            return LogResult(entryID: entry.id, written: [], healthError: error.localizedDescription, storeError: nil)
        }
        entry.written = written
        entry.present = written
        do {
            try context.save()
        } catch {
            AppLog.store.error("could not record written nutrients: \(error.localizedDescription, privacy: .public)")
            return LogResult(entryID: entry.id, written: written, healthError: nil, storeError: error.localizedDescription)
        }
        return LogResult(entryID: entry.id, written: written, healthError: nil, storeError: nil)
    }

    private func saveQuietly(_ what: String) {
        do {
            try context.save()
        } catch {
            AppLog.store.error("could not \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
