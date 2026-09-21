import Foundation
import os
import SwiftData

/// Creates the local entry, then mirrors it to Health; deletes mirror to Health first.
/// Shared by the Quantity sheet and the swipe actions on Today. Main-actor because it
/// drives a `ModelContext`. Logging from an Add-sheet choice lives in `EntryLogger+Choice`.
struct EntryLogger {
    let context: ModelContext
    let health: any HealthWriting

    /// Re-logs an entry as the repeat action does: same amount at `timestamp`, meal slot
    /// inferred from it. A custom food that still exists is recomputed from its current
    /// values, since the user may have corrected them; a recipe and any entry without a
    /// live food link are copied from the frozen snapshot. Links are copied for display.
    func repeatEntry(_ entry: LogEntry, at timestamp: Date) async throws -> LogResult {
        let live = entry.food.flatMap { $0.kind == .custom ? $0 : nil }
        let copy = LogEntry(
            timestamp: timestamp,
            mealSlot: MealSlot.inferred(from: timestamp),
            foodName: live?.name ?? entry.foodName,
            grams: entry.grams,
            snapshot: live.map { SnapshotMath.snapshot(per100g: $0.per100g, grams: entry.grams) } ?? entry.snapshot
        )
        context.insert(copy)
        copy.servings = entry.servings
        copy.food = entry.food
        copy.recipe = entry.recipe
        entry.food?.noteUsed(grams: entry.grams, at: Date.now)
        if let servings = entry.servings {
            entry.recipe?.noteUsed(servings: servings, at: Date.now)
        }
        try context.save()
        AppLog.store.info("logged \(copy.id.uuidString, privacy: .public) again from \(entry.id.uuidString, privacy: .public)")
        return await mirror(copy)
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

    /// Re-saves the entry's whole set to Health under a bumped version, which replaces
    /// whatever is still there, then records what went out as both written and present.
    /// The bump is saved first, and throws if it cannot be, so no version is ever reused.
    func restore(_ entry: LogEntry) async throws -> LogResult {
        entry.syncVersion += 1
        try context.save()
        AppLog.store.info("restoring \(entry.id.uuidString, privacy: .public) as version \(entry.syncVersion)")
        return await mirror(entry)
    }

    /// Writes the entry's snapshot to Health and records what went out. Health failures
    /// and the follow-up save report through the result; the entry itself is already saved.
    func mirror(_ entry: LogEntry) async -> LogResult {
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
