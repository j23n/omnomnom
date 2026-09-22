import Foundation
import os
import SwiftData

/// Creates the local entry, then mirrors it to Health; deletes mirror to Health first,
/// edits re-save under a bumped version. Shared by the Quantity sheet, the entry editor
/// and the swipe actions on Today. Main-actor because it drives a `ModelContext`.
/// Logging from an Add-sheet choice lives in `EntryLogger+Choice`.
struct EntryLogger {
    let context: ModelContext
    let health: any HealthWriting

    /// Re-logs an entry as the repeat action does: same amount at `timestamp`, in
    /// `mealSlot` or, when `nil`, the slot inferred from the time. A custom food or
    /// product that still exists is recomputed from its current values, since the user
    /// may have corrected them; a recipe and any entry without a live food link are
    /// copied from the frozen snapshot. Links and the estimate flag are copied for display.
    func repeatEntry(_ entry: LogEntry, at timestamp: Date, mealSlot: MealSlot? = nil) async throws -> LogResult {
        let live = entry.food.flatMap { $0.kind == .custom || $0.kind == .product ? $0 : nil }
        let copy = LogEntry(
            timestamp: timestamp,
            mealSlot: mealSlot ?? MealSlot.inferred(from: timestamp),
            foodName: live?.name ?? entry.foodName,
            grams: entry.grams,
            snapshot: live.map { SnapshotMath.snapshot(per100g: $0.per100g, grams: entry.grams) } ?? entry.snapshot
        )
        context.insert(copy)
        copy.servings = entry.servings
        copy.isEstimate = entry.isEstimate
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

    /// Applies a corrected amount, meal slot and time to an entry that is already
    /// logged, then mirrors the whole entry to Health again under a bumped version.
    /// `amount` is grams or servings, as `basis` says; the snapshot is scaled from the
    /// entry's own frozen values, never from the linked food.
    ///
    /// There is no delete step on the Health side. The set of nutrients written is the
    /// snapshot's non-nil values intersected with the types Health authorizes, and
    /// scaling never turns a value into `nil`, so at an unchanged authorization an edit
    /// cannot shrink that set and leave stale samples behind. A higher `syncVersion`
    /// under the same sync identifier replaces the samples that are there, including
    /// their dates, so moving the entry in time is covered too.
    func update(
        _ entry: LogEntry, amount: Double, basis: EntryAmountBasis, mealSlot: MealSlot, at timestamp: Date
    ) async throws -> LogResult {
        entry.grams = basis.grams(for: amount)
        entry.servings = basis.isServings ? amount : nil
        entry.snapshot = basis.snapshot(for: amount)
        return try await commitEdit(entry, mealSlot: mealSlot, at: timestamp)
    }

    /// The same edit with the amount left alone: for an entry there is nothing to scale,
    /// and for one whose amount the user did not touch, so the rounding the field applies
    /// to a displayed value never writes itself back. The snapshot and the grams stand.
    func update(_ entry: LogEntry, mealSlot: MealSlot, at timestamp: Date) async throws -> LogResult {
        try await commitEdit(entry, mealSlot: mealSlot, at: timestamp)
    }

    /// Saves the edited entry or leaves the store untouched, then re-mirrors it.
    private func commitEdit(_ entry: LogEntry, mealSlot: MealSlot, at timestamp: Date) async throws -> LogResult {
        entry.mealSlot = mealSlot
        entry.timestamp = timestamp
        entry.syncVersion += 1
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.store.error("edit failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        AppLog.store.info("edited \(entry.id.uuidString, privacy: .public) as version \(entry.syncVersion)")
        let result = await mirror(entry)
        if result.healthError != nil {
            // Health still holds the numbers from before the edit, so the entry is no
            // longer the one that was written: say so rather than let the row read as
            // synced. An empty `present` against a non-empty `written` derives `gone`,
            // which badges the row and offers to write it again.
            entry.present = []
            saveQuietly("record the edit as missing from Health")
        }
        return result
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
        entry.releasePhoto(in: context)
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
    ///
    /// The `orphaned` flag is cleared: it says a local delete could not be mirrored, and
    /// writing the entry again makes that untrue. `HealthState.derive` reads the flag
    /// before anything else, so leaving it set would freeze the entry in that state.
    func restore(_ entry: LogEntry) async throws -> LogResult {
        entry.orphaned = false
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
