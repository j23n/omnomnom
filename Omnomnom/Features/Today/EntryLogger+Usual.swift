import Foundation

/// What came of offering a slot's usual meal.
nonisolated enum UsualOutcome: Sendable {
    /// Written, with the way back from it.
    case logged(LoggedLine)
    /// One of the foods the line names no longer exists, so nothing was written.
    case gone

    /// What to tell the user, which is a sentence either way.
    var message: String {
        switch self {
        case .logged(let line): line.message
        case .gone: "That meal can't be logged any more: one of its foods is gone."
        }
    }
}

extension EntryLogger {
    /// Logs a slot's usual line, marked as assumed.
    ///
    /// The only place in the app an entry is written without anyone describing it, and it
    /// still takes a tap. `EntryOrigin.baseline` is what keeps the day distinguishable
    /// afterwards: it reads as assumed rather than complete, and any mean including it says
    /// so. Shared by the proposal card on Today and the loose-ends queue, which offer the
    /// same thing in two places and must not do it two ways.
    func logUsual(
        _ phrase: Phrase, for slot: MealSlot, on day: Date, resolver: LineResolver
    ) async -> UsualOutcome {
        guard let resolution = resolver.resolution(for: phrase) else { return .gone }
        let timestamp = QuantitySheet.defaultTimestamp(on: day)
        let outcome = await logLine(resolution, mealSlot: slot, at: timestamp, origin: .baseline)
        phrase.noteRecalled()
        return .logged(LoggedLine(resolution: resolution, outcome: outcome))
    }
}
