import Foundation
import Observation

/// Where the app should go when something outside it asked.
///
/// Visual intelligence shows the app's foods in its own results, and tapping one runs
/// an `OpenIntent` in this process. The intent has no view to push, so it leaves the
/// food here and Today picks it up. One slot, taken once: a second tap replaces a
/// choice nobody acted on rather than queueing behind it.
@Observable
final class AppRouter {
    /// A food the system asked the app to open, still waiting to be shown.
    private(set) var pendingChoice: FoodChoice?

    func open(_ choice: FoodChoice) {
        pendingChoice = choice
    }

    /// Clears the slot. Called by whoever took the choice, so the same food is not
    /// opened again when the screen comes back.
    func clearPendingChoice() {
        pendingChoice = nil
    }

    /// A line Siri took that could not be logged outright, waiting for the composer.
    ///
    /// Separate from `pendingChoice` because they arrive from different places and are
    /// taken by different screens, and because a line and a food are not alternatives:
    /// a spoken sentence can leave a line here while a tapped result leaves a food.
    private(set) var pendingLine: String?

    func compose(_ line: String) {
        pendingLine = line
    }

    func clearPendingLine() {
        pendingLine = nil
    }
}
