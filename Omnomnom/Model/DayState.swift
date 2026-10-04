import Foundation

/// What kind of day the app is looking at.
///
/// A day that was not fully logged is the normal case, not a failure, and the app has to
/// be able to say which kind it has. Without that every average silently divides by days
/// holding nothing, and the overview is wrong in the one direction that matters: a
/// zero-kilocalorie Tuesday dragging a month down.
nonisolated enum DayState: String, Hashable, Sendable, CaseIterable {
    /// The user marked it done. The only state a mean is computed over.
    case complete
    /// Every entry came from a baseline proposal rather than from a description.
    ///
    /// Real enough to be in Health — the user accepted it — and not asserted carefully
    /// enough to be silent about. A mean that includes such days says how many.
    case assumed
    /// Entries exist and the day was not marked done.
    case partial
    /// No entries at all. Drawn as a gap, never as a zero.
    case empty

    /// Whether a mean may be computed over this day.
    var countsTowardMean: Bool { self == .complete }

    /// What a day says about itself on Today, always as a sentence and never as a share.
    ///
    /// "19 of 30 days" and "63 per cent" are the same fact, and the second grades the
    /// user's diligence — a worse failure than grading their diet, because the app's
    /// whole claim to stay a logging tool is that it does not grade, and diligence is not
    /// even the thing being measured.
    var note: String {
        switch self {
        case .complete: "Marked as everything for this day."
        case .assumed: "Taken from your usual day."
        case .partial: "Some of this day is logged."
        case .empty: "Nothing logged for this day."
        }
    }

    /// Derived from what the day holds and what the user said about it.
    ///
    /// Pure, so the rule is tested rather than argued about. `assumed` beats `complete`
    /// deliberately: a day accepted in one tap must not read as one someone described,
    /// however they marked it afterwards.
    static func derive(entryOrigins: [EntryOrigin], markedComplete: Bool) -> DayState {
        guard !entryOrigins.isEmpty else { return .empty }
        if entryOrigins.allSatisfy({ $0 == .baseline }) { return .assumed }
        return markedComplete ? .complete : .partial
    }
}
