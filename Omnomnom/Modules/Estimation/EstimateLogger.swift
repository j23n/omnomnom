import Foundation
import os
import SwiftData

/// What logging a draft produced: one `LogResult` per entry, folded into one banner.
nonisolated struct EstimationLogOutcome: Hashable, Sendable {
    let results: [LogResult]

    /// "Logged 3 estimated items." followed by each distinct problem, once.
    var bannerMessage: String {
        let count = results.count
        let logged = count == 1 ? "Logged 1 estimated item." : "Logged \(count) estimated items."
        var seen: Set<String> = []
        var problems: [String] = []
        for message in results.compactMap(\.bannerMessage) where seen.insert(message).inserted {
            problems.append(message)
        }
        return ([logged] + problems).joined(separator: " ")
    }
}

/// Logs the confirmed rows: one entry per item, flagged as an estimate, with the typed
/// values as its frozen snapshot and no food link. All entries are saved in one go and
/// then mirrored to Health one after another. Main-actor because it drives a `ModelContext`.
struct EstimateLogger {
    let context: ModelContext
    let health: any HealthWriting

    /// Throws only when the local save fails, after rolling the context back; Health
    /// outcomes are reported through the result, as everywhere else.
    func log(_ items: [EstimatedDraftItem], mealSlot: MealSlot, at timestamp: Date) async throws -> EstimationLogOutcome {
        var entries: [LogEntry] = []
        for item in items {
            let entry = LogEntry(
                timestamp: timestamp, mealSlot: mealSlot, foodName: item.name, grams: item.grams, snapshot: item.nutrition
            )
            entry.isEstimate = true
            context.insert(entry)
            entries.append(entry)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.store.error("estimate save failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        AppLog.estimation.info("logged \(entries.count) estimated entries")
        let logger = EntryLogger(context: context, health: health)
        var results: [LogResult] = []
        for entry in entries {
            results.append(await logger.mirror(entry))
        }
        return EstimationLogOutcome(results: results)
    }
}
