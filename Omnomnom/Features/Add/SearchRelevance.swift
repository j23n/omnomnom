import Foundation

/// How well a name answers a query, as one number, so hits from the Library, the
/// bundled database and Open Food Facts can be put in a single order.
///
/// Each source ranks its own hits by its own measure: SQLite's bm25, whatever
/// Elasticsearch decided, a plain `contains` test over the Library. Those numbers mean
/// nothing to each other, so none of them is used. Every candidate is scored here
/// instead, from the query and the row's own text, which is the only way one list can
/// be honest about its order. Pure, so that order is testable.
nonisolated enum SearchRelevance {
    /// Match tiers, best first. A better match always wins; the only weighting is the
    /// crowdsourcing penalty below, which decides a tie and nothing more.
    static let exact = 1.0
    static let prefix = 0.8
    static let wordPrefix = 0.65
    static let substring = 0.45
    static let everyToken = 0.3

    /// A row a source returned for a reason this app cannot see — Open Food Facts also
    /// matches categories and labels, which are not requested — still belongs in the
    /// list, under everything whose place can be explained.
    static let unexplained = 0.05

    /// How much of the name the query accounts for. This is what separates "Apple raw"
    /// from "Apple pie filling, canned" when both merely start with "apple".
    static let coverageWeight = 0.15

    /// What a crowdsourced row costs against a measured one at the same match, so that
    /// Open Food Facts and the bundled tables can be read as one list without a
    /// stranger's entry edging out a measured one on a coin toss.
    static let crowdsourcedPenalty = 0.04

    /// 0 when nothing matches, upwards from there when it does.
    ///
    /// The query is tried in the same forms the index is searched in, because a scorer
    /// that disagrees with the retriever about what a word is produces the worst possible
    /// outcome: a row that is found and then scored at zero. "Oats" finding "Oat flakes"
    /// and then refusing to rank it is how that was discovered — and worse, "Oat groats"
    /// did score, because "groats" happens to contain "oats".
    ///
    /// Not clamped at the top. A clamp made every strong match identical, so "Apple raw"
    /// and "Apple juice" both reached 1 and the tie fell to whichever had the lower id.
    /// Thresholds read the same either way, and ordering needs the headroom.
    static func score(name: String, query: String) -> Double {
        let folded = fold(name)
        guard !folded.isEmpty else { return 0 }
        return FoodQuery.forms(of: query)
            .map { scoreOneForm(name: folded, query: fold($0)) }
            .max() ?? 0
    }

    /// One already-folded query form against one already-folded name.
    private static func scoreOneForm(name: String, query: String) -> Double {
        guard !query.isEmpty, let tier = tier(name: name, query: query) else { return 0 }
        let coverage = min(1, Double(query.count) / Double(name.count))
        return max(0, tier + coverage * coverageWeight)
    }

    /// The best score over everything a row can be found by: its name, a brand, a tag.
    /// A recipe filed under "breakfast" is a good answer to "breakfast" even though its
    /// name says porridge.
    static func score(anyOf names: [String], query: String) -> Double {
        names.map { score(name: $0, query: query) }.max() ?? 0
    }

    /// The key the merged list is ordered by.
    static func rank(anyOf names: [String], query: String, bonus: Double) -> Double {
        max(score(anyOf: names, query: query), unexplained) + bonus
    }

    /// What a row's provenance is worth, added to the match.
    ///
    /// Only the crowdsourcing penalty is left. The user's own foods used to carry a
    /// bonus so they could hold their place in a list that mixed everything; they sit
    /// in a section of their own now, so they never meet these rows and a boost would
    /// move nothing.
    static func bonus(isCrowdsourced: Bool) -> Double {
        isCrowdsourced ? -crowdsourcedPenalty : 0
    }

    /// Casefolded, stripped of diacritics, whitespace collapsed — the same shape the
    /// bundled index is built in, so "Pomme" and "pomme" are one word here too.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Which tier a folded name sits in for a folded query, or `nil` for no match.
    private static func tier(name: String, query: String) -> Double? {
        if name == query { return exact }
        if name.hasPrefix(query) { return prefix }
        let words = words(of: name)
        if words.contains(where: { $0.hasPrefix(query) }) { return wordPrefix }
        if name.contains(query) { return substring }
        let tokens = query.split(separator: " ")
        if tokens.count > 1,
           tokens.allSatisfy({ token in words.contains { $0.hasPrefix(token) } }) {
            return everyToken
        }
        return nil
    }

    /// Words of a name, split on everything that is not a letter or a digit, so
    /// "Milk, whole, 3.25% milkfat" offers "milk", "whole", "3", "25" and "milkfat".
    private static func words(of folded: String) -> [Substring] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
