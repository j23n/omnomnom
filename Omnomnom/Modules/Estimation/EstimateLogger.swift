import Foundation
import os
import SwiftData

/// What logging a draft produced: one `LogResult` per entry that was saved, the rows
/// that were not, and whether a kept photo made it. Folded into one banner.
nonisolated struct EstimationLogOutcome: Hashable, Sendable {
    let results: [LogResult]
    /// Ids of the rows that reached the store, so the screen can drop what is committed
    /// and a second tap cannot log it again.
    let loggedRowIDs: [UUID]
    /// Names of the rows that could not be saved; logging stops at the first one.
    let failed: [String]
    /// True when the entries were saved but the kept photo could not be attached.
    let photoFailed: Bool

    init(results: [LogResult], loggedRowIDs: [UUID] = [], failed: [String] = [], photoFailed: Bool = false) {
        self.results = results
        self.loggedRowIDs = loggedRowIDs
        self.failed = failed
        self.photoFailed = photoFailed
    }

    /// "Logged 3 estimated items." followed by what did not work, each problem once.
    var bannerMessage: String {
        let count = results.count
        var sentences = [count == 1 ? "Logged 1 estimated item." : "Logged \(count) estimated items."]
        if !failed.isEmpty {
            sentences.append(
                failed.count == 1 ? "1 item could not be logged." : "\(failed.count) items could not be logged."
            )
        }
        if photoFailed {
            sentences.append("The photo could not be kept.")
        }
        var seen: Set<String> = []
        for message in results.compactMap(\.bannerMessage) where seen.insert(message).inserted {
            sentences.append(message)
        }
        return sentences.joined(separator: " ")
    }
}

/// Logs the confirmed rows: one ordinary entry per row, through the same path as the
/// Quantity sheet, so each one links its food, freezes that food's values for the
/// portion and mirrors to Health. Only the `isEstimate` flag, and the badge it puts on
/// Today, says the portion was estimated. A kept photo becomes one `Photo` row that
/// every entry of the estimate shares. Main-actor because it drives a `ModelContext`.
struct EstimateLogger {
    let context: ModelContext
    let health: any HealthWriting

    /// Each row is saved on its own, so the first one that fails stops the run and the
    /// rest are left for the user to retry: the outcome then names how many did not go
    /// in, and `loggedRowIDs` says which rows are committed. Throws only when nothing at
    /// all was logged. Health outcomes are reported through the results, as everywhere
    /// else. `photo` is the stored-size bytes to keep with the entries, or `nil` to keep
    /// nothing.
    func log(
        _ items: [ResolvedEstimateItem], mealSlot: MealSlot, at timestamp: Date, photo: Data? = nil
    ) async throws -> EstimationLogOutcome {
        let logger = EntryLogger(context: context, health: health)
        var results: [LogResult] = []
        var loggedRowIDs: [UUID] = []
        var failed: [String] = []
        var failure: (any Error)?
        for item in items {
            guard let choice = item.choice else { continue }
            do {
                let result = try await logger.log(
                    choice: choice, amount: item.grams, mealSlot: mealSlot, at: timestamp, isEstimate: true
                )
                results.append(result)
                loggedRowIDs.append(item.id)
            } catch {
                AppLog.store.error("estimated row not logged: \(error.localizedDescription, privacy: .public)")
                failed.append(item.name)
                failure = error
                break
            }
        }
        if results.isEmpty, let failure { throw failure }
        AppLog.estimation.info("logged \(results.count) estimated entries, \(failed.count) not logged")
        var photoFailed = false
        if let photo, !results.isEmpty {
            photoFailed = !keep(photo, with: results.map(\.entryID))
        }
        return EstimationLogOutcome(
            results: results, loggedRowIDs: loggedRowIDs, failed: failed, photoFailed: photoFailed
        )
    }

    /// Relates one `Photo` to every entry the estimate produced, and says whether that
    /// worked. The entries are already saved, so a failure here loses the photo and
    /// nothing else: it is rolled back and reported in the banner rather than thrown,
    /// which would read as if nothing had been logged.
    private func keep(_ data: Data, with ids: [UUID]) -> Bool {
        let shared = Photo(data: data)
        context.insert(shared)
        do {
            let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { ids.contains($0.id) })
            for entry in try context.fetch(descriptor) {
                entry.photo = shared
            }
            try context.save()
            return true
        } catch {
            context.rollback()
            AppLog.store.error("could not keep the estimate photo: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
