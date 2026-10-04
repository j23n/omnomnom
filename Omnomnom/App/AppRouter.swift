import Foundation
import Observation

/// Where the app should go when something outside it asked.
///
/// An app intent runs in this process with no view of its own to push, so it leaves what
/// it wants shown here and the screen that owns it picks it up. Taken once: a second
/// arrival replaces one nobody acted on rather than queueing behind it.
///
/// There is one slot. There were two, the other holding a food for the Quantity sheet,
/// put there by the intent behind visual intelligence; the camera belongs to the composer
/// now and nothing wrote that slot any more.
@Observable
final class AppRouter {
    /// A line Siri took that could not be logged outright, waiting for the composer.
    private(set) var pendingLine: String?

    func compose(_ line: String) {
        pendingLine = line
    }

    func clearPendingLine() {
        pendingLine = nil
    }
}
