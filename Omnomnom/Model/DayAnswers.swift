import Foundation

/// Which of a day's four meals have an answer, which is what the ring in the day mark draws.
///
/// An answer is not the same as food. "Nothing tonight" answers dinner, and a day where
/// every meal has been answered is closed whether or not anything was eaten at three of
/// them. That distinction is the whole reason a skipped slot has to be stored: the absence
/// of an entry cannot tell a meal nobody ate from a meal nobody recorded.
///
/// Named, never divided. This type offers the slots and their count and deliberately
/// offers no fraction or percentage, for the reason given in `DayState.note`.
nonisolated struct DayAnswers: Hashable, Sendable {
    /// Slots holding at least one entry.
    let logged: Set<MealSlot>
    /// Slots the user said held nothing.
    let skipped: Set<MealSlot>

    init(logged: Set<MealSlot>, skipped: Set<MealSlot> = []) {
        self.logged = logged
        self.skipped = skipped
    }

    /// From the meal slots of a day's entries, which is how Today already has them.
    init(entrySlots: some Sequence<MealSlot>, skipped: Set<MealSlot> = []) {
        self.init(logged: Set(entrySlots), skipped: skipped)
    }

    /// Nothing answered.
    static let empty = DayAnswers(logged: [])

    /// Every slot with an answer of either kind.
    var answered: Set<MealSlot> { logged.union(skipped) }

    /// The slots still owed an answer, in the order Today lists them.
    var unanswered: [MealSlot] { MealSlot.allCases.filter { !answered.contains($0) } }

    /// Whether all four have an answer. The condition the run counts.
    var isAnswered: Bool { unanswered.isEmpty }

    /// Whether this slot has an answer, of either kind.
    func isAnswered(_ slot: MealSlot) -> Bool { answered.contains(slot) }
}
