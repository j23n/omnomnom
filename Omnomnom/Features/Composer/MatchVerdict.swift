import Foundation
import FoundationModels

/// How sure the model is that a candidate is the food the line meant.
@Generable(description: "How sure a choice is")
nonisolated enum VerdictCertainty: String, Hashable, Sendable {
    case certain
    case probable
    case unsure

    /// The same certainty as a row's confidence.
    ///
    /// One mapping, because two paths read a verdict — the validator and the tool loop —
    /// and what "probable" is worth on a row must not depend on which of them answered.
    var confidence: MatchConfidence {
        switch self {
        case .certain: .settled
        case .probable: .probable
        case .unsure: .unsure
        }
    }
}

/// The model's answer for one item of a line.
///
/// An id and an enum, and nothing else. That is the point: the output cannot contain a
/// food the model invented or a nutrient value it made up, because there is nowhere in
/// this shape to put one. Every number still comes from the row the id names.
@Generable(description: "Which candidate food an item should resolve to")
nonisolated struct MatchVerdict: Hashable, Sendable {
    @Guide(description: "The number of the item this answers, exactly as it was listed")
    var item: Int

    @Guide(description: "The id of the chosen candidate food, or 0 when none of them is right")
    var candidate: Int

    @Guide(description: "How sure this choice is")
    var certainty: VerdictCertainty

    @Guide(description: "True only when the amount eaten and the chosen food do not go together, such as 200 g of a powder")
    var implausible: Bool

    init(item: Int, candidate: Int, certainty: VerdictCertainty, implausible: Bool = false) {
        self.item = item
        self.candidate = candidate
        self.certainty = certainty
        self.implausible = implausible
    }

    /// "None of these", which is a first-class answer: it is correct for a food the
    /// bundled tables do not hold, and it routes the item onward rather than forcing a
    /// wrong row on it.
    var isNone: Bool { candidate == 0 }
}

/// Every verdict for one line, answered in a single request.
@Generable(description: "One verdict per item in a meal, in the order the items were listed")
nonisolated struct MatchVerdicts: Hashable, Sendable {
    @Guide(description: "One entry per item, in the order given", .maximumCount(12))
    var verdicts: [MatchVerdict]

    init(verdicts: [MatchVerdict]) {
        self.verdicts = verdicts
    }

    /// The verdict for an item by its number, or `nil` when the model skipped it.
    func verdict(forItem number: Int) -> MatchVerdict? {
        verdicts.first { $0.item == number }
    }
}
