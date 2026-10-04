import Foundation
import SwiftData

/// A line the user typed, and what it resolved to last time.
///
/// This is the memory the whole natural-language path runs on, and it is deliberately
/// not a library. Nothing here is named, nothing accumulates where the user has to tend
/// it, and they are never asked whether a meal was worth keeping. Eating the same thing
/// twice is what makes the second time free.
///
/// One table serves two jobs that look different and are not. A phrase of one word with
/// one item is a synonym for a food — "flat white", "my bread" — and a phrase of a whole
/// sentence with four items is a remembered meal. The same lookup answers both, and the
/// same act writes both: logging a line records it, correcting a row rewrites it.
///
/// `Recipe` keeps its own job, a dish cooked in a batch and divided into servings.
/// Nothing here creates one.
@Model
final class Phrase {
    var id: UUID = UUID()
    /// The normalised key, from `PhraseKey.normalise`. Not unique in the schema, because
    /// a CloudKit-ready store cannot hold a unique index, so `recall` resolves it and
    /// `remember` is the only thing that writes one.
    var key: String = ""
    /// The line as the user last typed it, shown when a phrase is listed back to them.
    /// The key is what matching uses; this is only ever for reading.
    var text: String = ""
    var useCount: Int = 0
    var lastUsed: Date = Date.now
    /// Raw `MealSlot` this line was last logged in, so a baseline can be offered for the
    /// slot someone actually eats it at rather than asked about in a questionnaire.
    /// `nil` for a phrase written before the app recorded it.
    var lastSlotRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \PhraseItem.phrase)
    var items: [PhraseItem]?

    init(key: String, text: String) {
        self.id = UUID()
        self.key = key
        self.text = text
        self.useCount = 0
        self.lastUsed = Date.now
    }

    /// The meal slot this line was last logged in.
    var lastSlot: MealSlot? {
        get { lastSlotRaw.flatMap(MealSlot.init(rawValue:)) }
        set { lastSlotRaw = newValue?.rawValue }
    }

    /// The items in the order they were logged.
    var orderedItems: [PhraseItem] {
        (items ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Whether every item still points at a food or a recipe that exists.
    ///
    /// A phrase one of whose foods was deleted cannot be recalled whole: half a meal
    /// recalled silently would be worse than asking again.
    var isRecallable: Bool {
        let items = orderedItems
        return !items.isEmpty && items.allSatisfy(\.isResolvable)
    }

    // MARK: - Recall

    /// The phrase a typed line is filed under, or `nil` when there is none or when what
    /// is there can no longer be resolved.
    static func recall(_ line: String, in context: ModelContext) throws -> Phrase? {
        guard let key = PhraseKey.normalise(line) else { return nil }
        return try recall(key: key, in: context)
    }

    /// The same by an already-normalised key, for a parsed fragment.
    static func recall(key: String, in context: ModelContext) throws -> Phrase? {
        guard let found = try stored(key: key, in: context) else { return nil }
        return found.isRecallable ? found : nil
    }

    /// Every phrase, most recently used first, for the list in Settings.
    static func all(in context: ModelContext) throws -> [Phrase] {
        try context.fetch(
            FetchDescriptor<Phrase>(sortBy: [SortDescriptor(\Phrase.lastUsed, order: .reverse)])
        )
    }

    // MARK: - Writing

    /// Records what a line resolved to, replacing anything held for it before.
    ///
    /// Replacing rather than merging is the point: the user has just corrected the line,
    /// or logged it afresh, and either way what they settled on now is what the phrase
    /// means. A phrase that accumulated every past reading of itself would drift.
    ///
    /// Returns `nil` for a line with no key — nothing but filler words — and for one with
    /// no items, because there would be nothing to remember.
    @discardableResult
    static func remember(
        line: String, items: [PhraseDraftItem], in context: ModelContext, now: Date = .now,
        slot: MealSlot? = nil
    ) throws -> Phrase? {
        guard let key = PhraseKey.normalise(line), !items.isEmpty else { return nil }
        let phrase = try stored(key: key, in: context) ?? {
            let fresh = Phrase(key: key, text: line)
            context.insert(fresh)
            return fresh
        }()
        for existing in phrase.orderedItems {
            context.delete(existing)
        }
        phrase.items = []
        for (index, draft) in items.enumerated() {
            let item = PhraseItem(sortIndex: index, name: draft.name, amount: draft.amount)
            context.insert(item)
            item.food = draft.food
            item.recipe = draft.recipe
            item.phrase = phrase
        }
        phrase.text = line
        phrase.useCount += 1
        phrase.lastUsed = now
        if let slot { phrase.lastSlot = slot }
        return phrase
    }

    /// Marks a recalled phrase as used again, which is what orders the list and the
    /// widget. Separate from `remember` because recalling changes nothing but the
    /// ordering.
    func noteRecalled(at date: Date = .now) {
        useCount += 1
        lastUsed = date
    }

    /// The row for a key whether or not its items still resolve, which `remember` needs
    /// in order to overwrite one that no longer does.
    private static func stored(key: String, in context: ModelContext) throws -> Phrase? {
        let wanted: String = key
        var descriptor = FetchDescriptor<Phrase>(predicate: #Predicate<Phrase> { $0.key == wanted })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

/// One item on its way into a phrase: what it was called, how much of it, and the food
/// or recipe behind it.
///
/// `nonisolated`, and it has to be. A `@Model` type's members are nonisolated whatever
/// the target's default isolation says, so `Phrase.remember` reads this from a
/// nonisolated context; left on the default it would be main-actor and unreachable from
/// there. Legal because every stored property is a `let` — a mutable one could not be
/// nonisolated — and deliberately not `Sendable`, since it carries model references that
/// are not.
nonisolated struct PhraseDraftItem {
    let name: String
    /// In the food's own unit, or servings for a recipe.
    let amount: Double
    let food: Food?
    let recipe: Recipe?

    init(name: String, amount: Double, food: Food? = nil, recipe: Recipe? = nil) {
        self.name = name
        self.amount = amount
        self.food = food
        self.recipe = recipe
    }
}
