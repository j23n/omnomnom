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
    /// Match tiers, best first.
    ///
    /// At the same provenance a better match always wins. Across provenance the
    /// bonuses below deliberately reorder: a recipe you make every week beats a
    /// database row that merely starts with the same letters, which is the whole point
    /// of weighting them. The one thing the bonuses must never do is invent a match —
    /// a row whose place this app cannot explain stays under every row it can — and
    /// `SearchRelevanceTests` holds the numbers to that.
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

    /// What the user's own recipes and foods are worth: enough to win a tie against a
    /// stranger's row, never enough to beat a better match.
    static let ownBonus = 0.12
    /// What having logged something before is worth.
    static let familiarBonus = 0.08
    /// What a crowdsourced row costs against a measured one at the same match.
    static let crowdsourcedPenalty = 0.04

    /// 0 when nothing matches, up to 1 when the name is the query.
    static func score(name: String, query: String) -> Double {
        let name = fold(name)
        let query = fold(query)
        guard !name.isEmpty, !query.isEmpty, let tier = tier(name: name, query: query) else {
            return 0
        }
        let coverage = min(1, Double(query.count) / Double(name.count))
        return min(1, tier + coverage * coverageWeight)
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

    /// What a row's provenance and the user's history with it are worth, added to the
    /// match. A product saved in the Library counts as the user's own, however it got
    /// there; only a row still out on the network pays the crowdsourcing penalty.
    static func bonus(isLocal: Bool, isCrowdsourced: Bool, isFamiliar: Bool) -> Double {
        var total = 0.0
        if isLocal {
            total += ownBonus
        } else if isCrowdsourced {
            total -= crowdsourcedPenalty
        }
        if isFamiliar {
            total += familiarBonus
        }
        return total
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
