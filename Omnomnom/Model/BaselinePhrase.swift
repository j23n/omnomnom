import Foundation
import SwiftData

/// A line someone eats by default, attached to the meal it belongs to.
///
/// For a person whose breakfast does not vary, the cheapest possible log is no log. A
/// baseline lets Today offer that slot's usual line as a *proposal*: no entry exists, and
/// nothing has reached Health, until one tap accepts it. Typing into the slot replaces
/// the proposal, which is the deviation case and all most days need.
///
/// One rule keeps this sound and it is not negotiable: **nothing is written without a
/// tap.** A day nobody looked at must never appear in Health, because the value of the
/// whole overview rests on the figures being things this person actually asserted. The
/// accepted entries carry `EntryOrigin.baseline`, so such a day stays distinguishable
/// afterwards and reads as `assumed` rather than `complete`.
///
/// A baseline is only ever built from what the user already does — a line they have
/// logged repeatedly in that slot — and never from a questionnaire.
@Model
final class BaselinePhrase {
    var id: UUID = UUID()
    var mealSlotRaw: String = MealSlot.breakfast.rawValue
    var phrase: Phrase?
    /// When the user last turned this slot's proposal down. Declining is permanent until
    /// they ask again, because an offer that keeps coming back is nagging.
    var declinedAt: Date?

    init(mealSlot: MealSlot) {
        self.id = UUID()
        self.mealSlotRaw = mealSlot.rawValue
    }

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .breakfast }
        set { mealSlotRaw = newValue.rawValue }
    }

    /// Whether this is worth proposing: it points at a line that still resolves and the
    /// user has not turned it down.
    var isOfferable: Bool {
        declinedAt == nil && (phrase?.isRecallable ?? false)
    }

    // MARK: - Reading

    /// The baseline for one slot, if there is one.
    static func baseline(for slot: MealSlot, in context: ModelContext) throws -> BaselinePhrase? {
        let raw = slot.rawValue
        var descriptor = FetchDescriptor<BaselinePhrase>(
            predicate: #Predicate<BaselinePhrase> { $0.mealSlotRaw == raw }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Writing

    /// Makes a phrase the baseline for a slot, replacing whatever was there.
    @discardableResult
    static func set(_ phrase: Phrase, for slot: MealSlot, in context: ModelContext) throws -> BaselinePhrase {
        let baseline = try self.baseline(for: slot, in: context) ?? {
            let fresh = BaselinePhrase(mealSlot: slot)
            context.insert(fresh)
            return fresh
        }()
        baseline.phrase = phrase
        baseline.declinedAt = nil
        return baseline
    }

    /// Forgets the baseline for a slot entirely.
    static func clear(for slot: MealSlot, in context: ModelContext) throws {
        guard let baseline = try baseline(for: slot, in: context) else { return }
        context.delete(baseline)
    }
}
