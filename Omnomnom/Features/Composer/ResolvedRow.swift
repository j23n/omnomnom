import Foundation

/// Where a row's food came from, which is what the resolution sheet has to make plain.
nonisolated enum RowOrigin: Hashable, Sendable {
    /// The whole line came back from a phrase logged before.
    case phrase
    /// This one food came back from history, inside a line that is otherwise new.
    case item
    /// Matched in the bundled tables.
    case database
    /// Found in Open Food Facts, which is opt-in and online.
    case product

    /// Whether the user already asserted this, in which case there is nothing to check
    /// and no model call to wait for.
    var isRecalled: Bool {
        self == .phrase || self == .item
    }

    /// The short line under the food name. Deliberately a description of what happened
    /// rather than a warning about what did not: "Matched by name" is the honest reading
    /// of a row the model never saw, and it carries no implication of a defect.
    func detail(checked: Bool) -> String {
        switch self {
        case .phrase: "From a line you logged before"
        case .item: "From what you logged before"
        case .database: checked ? "Checked" : "Matched by name"
        case .product: checked ? "Checked, Open Food Facts" : "Matched by name, Open Food Facts"
        }
    }
}

/// One row of the resolution sheet: a food, how much of it, and how sure that is.
nonisolated struct ResolvedRow: Identifiable, Hashable, Sendable {
    let id: UUID
    /// What the line called this, shown when there is no food to name it.
    var name: String
    /// The food every value on the row comes from. `nil` means nothing matched, and a
    /// row with no food carries no values and cannot be logged.
    var choice: FoodChoice?
    /// The amount in the food's own unit, or servings for a recipe.
    var amount: Double
    /// The step the amount came from, when there was a reference to multiply. `nil` on a
    /// food eaten for the first time, where "usual" would mean nothing and the row shows
    /// a portion or a plain figure instead.
    var bucket: AmountBucket?
    var origin: RowOrigin
    var confidence: MatchConfidence
    /// Set when the model judged the amount and the food not to go together.
    var implausible: Bool

    init(
        id: UUID = UUID(), name: String, choice: FoodChoice?, amount: Double,
        bucket: AmountBucket? = nil, origin: RowOrigin, confidence: MatchConfidence,
        implausible: Bool = false
    ) {
        self.id = id
        self.name = name
        self.choice = choice
        self.amount = amount
        self.bucket = bucket
        self.origin = origin
        self.confidence = confidence
        self.implausible = implausible
    }

    /// What the matched food holds in this amount; `nil` while nothing is matched.
    var nutrition: Nutrition? {
        choice?.snapshot(for: amount)
    }

    /// Whether this row stops the line being logged.
    var blocks: Bool {
        choice == nil || confidence == .unsure
    }

    /// Whether the row is settled enough to need no attention.
    var isSettled: Bool {
        !blocks && confidence == .settled && !implausible
    }

    /// The name to show: the food's, or what the line called it when there is no food.
    var displayName: String {
        choice?.name ?? name
    }
}

/// A whole line, resolved.
nonisolated struct LineResolution: Identifiable, Hashable, Sendable {
    /// Fresh per resolution, so re-resolving the same line presents a new sheet rather
    /// than reusing the one that is up.
    let id: UUID
    /// The line as typed, which is what a phrase is remembered under.
    let line: String
    var rows: [ResolvedRow]
    /// Whether the model checked this line's database matches.
    ///
    /// All-or-nothing by design: either every retrieved row was checked or none was. It
    /// matters because "not checked" then describes the screen, which one sentence can
    /// carry, rather than describing individual rows, which would need a fourth per-row
    /// marker competing with three confidences for space the sheet does not have. A
    /// model that fails or times out partway through a line counts as absent for the
    /// whole line.
    let wasChecked: Bool

    /// Nothing was found in the line at all.
    var isEmpty: Bool { rows.isEmpty }

    /// Whether Log should do anything.
    var canLog: Bool {
        !rows.isEmpty && !rows.contains(where: \.blocks)
    }

    /// Rows that are logged but want a look. This count is the one element on the sheet
    /// carrying the whole weight of that state, since row height is a weak signal and no
    /// colour may encode a verdict.
    var glanceCount: Int {
        rows.filter { !$0.blocks && ($0.confidence == .probable || $0.implausible) }.count
    }

    /// Rows that stop the log, which is what the button explains itself by.
    var blockingCount: Int {
        rows.filter(\.blocks).count
    }

    init(id: UUID = UUID(), line: String, rows: [ResolvedRow], wasChecked: Bool) {
        self.id = id
        self.line = line
        self.rows = rows
        self.wasChecked = wasChecked
    }

    /// Everything the line comes to, over the rows that have a food.
    var total: Nutrition {
        rows.compactMap(\.nutrition).reduce(.empty, +)
    }
}
