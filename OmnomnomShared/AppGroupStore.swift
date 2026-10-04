import Foundation
import os

/// The small amount of state the app and its widget share.
///
/// **Not the SwiftData store.** The widget reads a snapshot the app writes, and nothing
/// more. Three reasons, in order of how much they matter:
///
/// 1. A widget extension is the wrong place to write to HealthKit, and logging a meal
///    means writing eight samples and a correlation. That belongs in the app.
/// 2. Sharing the store would mean the whole model layer in both targets — the entities,
///    the logger, the Health actor, the resolver — which is a local Swift package and a
///    refactor, not a widget.
/// 3. It leaves the store exactly where it is. Putting a SwiftData store into an App
///    Group moves its container, which is a data migration for anyone who already has
///    entries. Avoiding that is worth more than saving a screen transition.
///
/// So the widget shows what to log and the app does the logging, which is also the
/// arrangement that keeps the rule about nothing being written without a tap intact: the
/// tap happens on the widget and the entry appears in the app, where it can be seen.
nonisolated enum AppGroupStore {
    /// Must match the App Group in both targets' entitlements.
    static let identifier = "group.com.j23n.omnomnom"

    /// Where the snapshot lives, or `nil` when the group is not available — a missing
    /// entitlement, or a simulator that has not been set up for it. Everything here
    /// degrades to doing nothing rather than failing: the app works without a widget.
    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent("widget-snapshot.json")
    }

    /// Writes the snapshot, replacing whatever was there.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            AppGroupLog.widget.error("snapshot not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reads the snapshot, or an empty one when there is nothing yet.
    static func read() -> WidgetSnapshot {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else {
            return .empty
        }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}

/// Logging shared by both targets. Separate from the app's own `AppLog` because the
/// widget cannot see it.
nonisolated enum AppGroupLog {
    static let widget = Logger(subsystem: "com.j23n.omnomnom", category: "widget")
}
