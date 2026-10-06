import Foundation
import os

/// What one send wrote, kept so it can be taken back.
///
/// A line is logged the moment it is understood, with nothing to sign off first. That is
/// the point of the redesign and it is only defensible because of this type: the way back
/// is one tap, it names what it would remove, and it is offered next to the field the
/// words were typed into rather than somewhere else.
///
/// It holds entry identifiers and not entries, because an entry is a stored object bound
/// to a context and this crosses from the logging task to the view that offers the undo.
nonisolated struct LoggedLine: Identifiable, Hashable, Sendable {
    /// Fresh per send, so two identical lines are two offers rather than one.
    let id: UUID
    /// The line as typed, which is what the undo names.
    let line: String
    /// The entries the send created, in the order of the line.
    let entryIDs: [UUID]
    /// Rows that were written but want a look: a probable match, or an amount the model
    /// itself doubted.
    let marked: Int
    /// Rows that had a food and still could not be written.
    let failed: Int
    /// Trouble worth saying once, from the rows that did write — Health refusing, mostly.
    let notes: [String]

    var count: Int { entryIDs.count }

    /// Whether there is anything to take back. False when a send wrote nothing, where an
    /// Undo button would be a control for undoing nothing.
    var canUndo: Bool { !entryIDs.isEmpty }

    /// "Logged 4 items. 1 wants a look."
    ///
    /// Counts and never fractions, for the reason in `DayState.note`: a number of things
    /// done is a fact, and a proportion of a day is a judgement about how much a day
    /// should hold.
    var message: String {
        guard count > 0 else { return "Nothing could be logged from that line." }
        var parts = [count == 1 ? "Logged 1 item." : "Logged \(count) items."]
        if marked > 0 {
            parts.append(marked == 1 ? "1 wants a look." : "\(marked) want a look.")
        }
        if failed > 0 {
            parts.append(failed == 1 ? "1 could not be logged." : "\(failed) could not be logged.")
        }
        parts.append(contentsOf: notes)
        return parts.joined(separator: " ")
    }

    init(
        id: UUID = UUID(), line: String, entryIDs: [UUID], marked: Int, failed: Int,
        notes: [String] = []
    ) {
        self.id = id
        self.line = line
        self.entryIDs = entryIDs
        self.marked = marked
        self.failed = failed
        self.notes = notes
    }

    /// What logging one resolved line came to.
    ///
    /// `resolution` is the rows that were offered to the log, which is what the user signed
    /// off: the counts are about what reached the day rather than about what was typed.
    init(resolution: LineResolution, outcome: LineLogOutcome, id: UUID = UUID()) {
        var seen: Set<String> = []
        self.init(
            id: id,
            line: resolution.line,
            entryIDs: outcome.results.map(\.entryID),
            marked: resolution.glanceCount,
            failed: outcome.failed,
            notes: outcome.results.compactMap(\.bannerMessage).filter { seen.insert($0).inserted }
        )
    }
}

/// How an undo went.
nonisolated struct UndoOutcome: Hashable, Sendable {
    /// Entries removed here and, where they reached it, from Health.
    let removed: Int
    /// Entries that could not be removed, which stay on the day where they can be seen
    /// and dealt with one at a time.
    let kept: Int

    /// What to say afterwards, or `nil` when everything went back and the day showing one
    /// fewer meal says it better than a sentence would.
    var message: String? {
        guard kept > 0 else { return nil }
        if removed == 0 {
            return kept == 1
                ? "That entry could not be taken back."
                : "Those \(kept) entries could not be taken back."
        }
        let left = kept == 1
            ? "1 is still on the day."
            : "\(kept) are still on the day."
        return "Took back \(removed). \(left)"
    }
}

extension EntryLogger {
    /// Takes back everything one send wrote.
    ///
    /// Each entry goes through the same delete the swipe action uses, so Health is mirrored
    /// first and an entry it refuses to let go of stays visible rather than disappearing
    /// here and surviving there.
    ///
    /// What the line taught is left alone. The memory says this wording means these foods,
    /// which an undo does not make untrue — a send taken back because the reading was wrong
    /// is re-sent corrected, and `Phrase.remember` replaces that wording's items when it is.
    func undo(_ logged: LoggedLine) async -> UndoOutcome {
        var removed = 0
        var kept = 0
        for entryID in logged.entryIDs {
            guard let entry = entry(id: entryID) else {
                // Already gone, by a swipe or an edit. Nothing to take back and nothing
                // to report: the user has had their way with it either way.
                continue
            }
            switch await delete(entry) {
            case .deleted:
                removed += 1
            case .orphaned, .failed:
                kept += 1
            }
        }
        AppLog.store.info("undid \(removed) of \(logged.entryIDs.count) entries from one line")
        return UndoOutcome(removed: removed, kept: kept)
    }
}
