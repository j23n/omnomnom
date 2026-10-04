import Foundation

/// How sure the matcher is that a row is the food someone meant.
///
/// Three values rather than a number on screen, because the only thing the interface
/// has to decide is whether to ask. The number stays here where it can be tuned.
nonisolated enum MatchConfidence: String, Hashable, Sendable, CaseIterable {
    /// Good enough to log without asking.
    case settled
    /// Logged, and marked for a glance. The user can change it in one tap.
    case probable
    /// Not good enough to stand. Blocks the log until a food is picked or the row goes.
    case unsure
}

/// One candidate row with the score the matcher is willing to defend for it.
nonisolated struct FoodMatch: Identifiable, Hashable, Sendable {
    let food: BundledFood
    /// Relevance, after the ingredient penalty and the popularity prior. 0 to 1.
    let score: Double

    var id: Int { food.id }

    /// An ingredient form is always `unsure`, whatever it scored.
    ///
    /// Not merely "never settled". Typing "coffee" scores the powder at about 0.49
    /// after its penalty, which is `probable` — logged, with a marker — and a marker
    /// is not enough for a row that is wrong by a factor of a hundred. The flag means
    /// the row does not log itself at all; the user picks it deliberately or not at
    /// all. Someone really logging olive oil pays one tap for that, which is the right
    /// price.
    var confidence: MatchConfidence {
        if food.isIngredient { return .unsure }
        if score >= FoodMatcher.settledAt { return .settled }
        if score >= FoodMatcher.probableAt { return .probable }
        return .unsure
    }
}

/// Picking one bundled row for a term, and knowing when it should not have.
///
/// `SearchRelevance` orders a list for a person to read and choose from, which is a
/// different job: a mediocre order is corrected by the eye. Here nobody is looking
/// yet, so what matters is not the order but whether the top of it deserves to be
/// logged unasked. That needs a score with thresholds attached and an honest answer
/// of "not sure" available, and it is why this is a separate type rather than another
/// function on the scorer.
///
/// Pure, so the thresholds can be settled against a fixture set of real typed lines
/// rather than by argument. Everything the model adds on top of this lands in the
/// validation step; this is what runs when there is no model to ask.
nonisolated enum FoodMatcher {
    /// At or above this, a row is logged without asking.
    static let settledAt = 0.78
    /// At or above this, a row is logged and marked. Below, it blocks.
    static let probableAt = 0.42

    /// What an ingredient form gives up. Large on purpose, and larger than the gap
    /// between any two match tiers, so a powder never outranks the drink that shares
    /// its name however the two happen to score.
    static let ingredientPenalty = 0.35

    /// What the curated frequency column is worth, and the most it can ever be.
    ///
    /// Small, because a prior should break a tie rather than decide a match. Auto-
    /// picking leans on this far harder than interactive search ever did, and the
    /// curated list is written against FDC descriptions, so against a Ciqual and BLS
    /// build every row scores zero here and this term vanishes. That is a gap in the
    /// data rather than in the mechanism, and it is recorded as such.
    static let popularityWeight = 0.012
    static let popularityCeiling = 0.06

    /// The adjusted score for one row, or 0 when nothing in it answers the term.
    ///
    /// Scored over every name the row carries, not only the one it displays, so a
    /// French query reaches a Ciqual row that reads in English.
    static func score(_ food: BundledFood, term: String) -> Double {
        let base = SearchRelevance.score(anyOf: food.searchableNames, query: term)
        guard base > 0 else { return 0 }
        let prior = min(popularityCeiling, Double(max(0, food.popularity)) * popularityWeight)
        let penalty = food.isIngredient ? ingredientPenalty : 0
        return min(1, max(0, base + prior - penalty))
    }

    /// Candidates worth considering, best first, dropping what does not match at all.
    ///
    /// Ingredient forms are kept rather than removed. They are what the user meant
    /// often enough to matter — someone does log olive oil — and when they are not,
    /// the validation step needs to see them in order to reject them. Demoted, not
    /// hidden.
    ///
    /// Ties break by id so that one term always resolves the same way; a matcher that
    /// answers differently on two runs cannot be tested against a fixture set.
    static func shortlist(_ candidates: [BundledFood], term: String, limit: Int = 8) -> [FoodMatch] {
        candidates
            .map { FoodMatch(food: $0, score: score($0, term: term)) }
            .filter { $0.score > 0 }
            .sorted { $0.score == $1.score ? $0.food.id < $1.food.id : $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// The one row to take for a term, or `nil` when nothing matched at all.
    ///
    /// A result is always returned when anything matched, carrying its confidence; it
    /// is the caller's business whether that is good enough to log. Returning `nil`
    /// for a weak match would throw away the row the user most likely wants to be
    /// shown and corrected.
    static func best(_ candidates: [BundledFood], term: String) -> FoodMatch? {
        shortlist(candidates, term: term, limit: 1).first
    }
}
