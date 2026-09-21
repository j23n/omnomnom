import Foundation
import os
import SwiftData

/// Brings the local store in line with what Health still holds. Main-actor because it
/// edits `LogEntry` rows through the main context; the queries run inside the Health
/// actor. Nothing here reaches the UI as an error: every failure is logged, and the
/// anchors are only advanced once a batch was applied, so the next run retries it.
final class ReconcileService {
    private let context: ModelContext
    private let health: any HealthObserving
    private let defaults: UserDefaults
    /// The run in flight, awaited by every caller so an observer wake's completion
    /// handler fires only after its change was handled.
    private var current: Task<Void, Never>?
    private var runAgain = false

    init(context: ModelContext, health: any HealthObserving, defaults: UserDefaults = .standard) {
        self.context = context
        self.health = health
        self.defaults = defaults
    }

    /// Applies every change since the stored anchors. A call that arrives while one runs
    /// folds into one follow-up run and waits for it, so launch, scene activation and
    /// observer wakes never interleave on the same anchors and none returns before its
    /// change was applied. At start-up that is the launch run plus the eight observer
    /// queries, which each fire once on registration: at most one follow-up run.
    func reconcileAll() async {
        if let current {
            runAgain = true
            await current.value
            return
        }
        let task = Task {
            repeat {
                self.runAgain = false
                await self.runOnce()
            } while self.runAgain
            self.current = nil
        }
        current = task
        await task.value
    }

    private func runOnce() async {
        let anchors = HealthAnchors.load(from: defaults)
        let changes: HealthChanges
        do {
            changes = try await health.changes(since: anchors)
        } catch {
            AppLog.health.error("reconcile: reading changes failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let ids = Array(Reconciler.affectedEntryIDs(in: changes))
        if !ids.isEmpty || !changes.fullyRead.isEmpty {
            do {
                try apply(changes, to: ids)
            } catch {
                AppLog.store.error("reconcile: applying changes failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        do {
            try changes.anchors.save(to: defaults)
        } catch {
            AppLog.health.error("reconcile: could not store anchors: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetches the rows the batch names, or every row when a type was read in full (then
    /// any entry may have lost samples), applies the plan and saves once.
    private func apply(_ changes: HealthChanges, to ids: [UUID]) throws {
        let descriptor = changes.fullyRead.isEmpty
            ? FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { ids.contains($0.id) })
            : FetchDescriptor<LogEntry>()
        let entries = try context.fetch(descriptor)
        let snapshot = entries.map { ReconcileEntry(id: $0.id, written: $0.written, present: $0.present, timestamp: $0.timestamp) }
        let plan = Reconciler.plan(entries: snapshot, changes: changes)
        for nutrient in plan.unpruned {
            AppLog.health.notice("full read of \(nutrient.rawValue, privacy: .public) returned nothing, not pruning")
        }
        guard !plan.isEmpty else {
            AppLog.health.info("reconcile: \(changes.added.count) added, \(changes.deleted.count) deleted, nothing to update")
            return
        }
        for entry in entries {
            if let present = plan.present[entry.id] {
                entry.present = present
            }
        }
        try context.save()
        AppLog.health.info("reconcile: updated \(plan.present.count) of \(entries.count) affected entries")
    }
}
