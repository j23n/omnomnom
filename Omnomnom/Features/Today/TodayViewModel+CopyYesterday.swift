import Foundation
import os

extension TodayViewModel {
    /// Re-logs each of yesterday's `entries` at the same time of day today, never later
    /// than now, keeping its meal slot and mirroring it to Health as a repeat does. One
    /// banner sums it up, followed by each distinct problem Health reported, once.
    func copyPreviousDay(_ entries: [LogEntry], using logger: EntryLogger, now: Date = .now) async {
        var results: [LogResult] = []
        for entry in entries {
            guard let sameTimeToday = calendar.date(byAdding: .day, value: 1, to: entry.timestamp) else { continue }
            let timestamp = min(sameTimeToday, now)
            do {
                results.append(try await logger.repeatEntry(entry, at: timestamp, mealSlot: entry.mealSlot))
            } catch {
                AppLog.store.error("copy from yesterday failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        show(banner: Self.copiedMessage(results))
    }

    /// "Copied 3 entries from yesterday." plus the distinct problems, or the failure when
    /// nothing could be copied.
    static func copiedMessage(_ results: [LogResult]) -> String {
        let copied: String
        switch results.count {
        case 0: return "Could not copy yesterday's entries."
        case 1: copied = "Copied 1 entry from yesterday."
        default: copied = "Copied \(results.count) entries from yesterday."
        }
        var seen: Set<String> = []
        var problems: [String] = []
        for message in results.compactMap(\.bannerMessage) where seen.insert(message).inserted {
            problems.append(message)
        }
        return ([copied] + problems).joined(separator: " ")
    }
}
