import Foundation

/// How an entry came to exist.
///
/// Display and coverage information only. Nothing in the write path branches on it: an
/// entry typed and an entry accepted from a baseline are written to Health identically,
/// because both are things this person asserted. What it buys is the ability to say so
/// afterwards — a day accepted from a proposal is `assumed` rather than `complete`, and a
/// mean that includes such days says how many.
nonisolated enum EntryOrigin: String, Hashable, Sendable, CaseIterable {
    /// Typed into the composer.
    case typed
    /// Dictated into the composer.
    case dictated
    /// Confirmed from a photo estimate.
    case photo
    /// Picked in the food search screen.
    case picked
    /// Logged again from an entry that already existed, or copied from another day.
    case repeated
    /// Accepted from the day's baseline proposal rather than described.
    case baseline

    /// Whether the user described this rather than accepting a suggestion. What makes a
    /// day's totals something they stood behind.
    var isAsserted: Bool {
        self != .baseline
    }
}
