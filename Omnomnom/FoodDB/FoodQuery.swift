import Foundation

/// Builds FTS5 MATCH expressions. Pure and tested.
nonisolated enum FoodQuery {
    /// Turns free text into an FTS5 expression: each word is double-quoted and
    /// prefix-matched with `*`. Returns `nil` when the text holds no words.
    ///
    /// A token that looks like a plural is searched in both forms, because FTS5's prefix
    /// match only works forwards. `"oat"*` finds "Oat flakes"; `"oats"*` finds nothing at
    /// all, and the German table calls the food "Oat flakes". Typing the plural of a food
    /// is not an unusual thing to do, so without this the most ordinary breakfast in the
    /// database is unreachable — which is how it was found.
    static func ftsMatchExpression(for text: String) -> String? {
        let tokens = words(of: text).map(String.init)
        guard !tokens.isEmpty else { return nil }
        // Joined with an explicit AND rather than a space. FTS5's implicit AND does not
        // accept a parenthesised group beside a bare term — `"oat"* ("flakes"* OR
        // "flake"*)` is a syntax error — and spelling the operator out is valid in every
        // combination. Found by running the expressions against the real index.
        return tokens.map(clause(for:)).joined(separator: " AND ")
    }

    /// The words of a food name, or of something typed to look one up.
    ///
    /// Split on everything that is not a letter or a digit, so "Milk, whole, 3.25% milkfat"
    /// offers "Milk", "whole", "3", "25" and "milkfat". One definition for both sides,
    /// which is the whole point of it living here: the scorer used to split a query on
    /// spaces while splitting names on punctuation, so a query word arrived carrying a
    /// comma and could never match a name word that had been stripped of one. Every term
    /// in the wording a composition table uses — "Pasta, cooked", "Pizza, Margherita" —
    /// scored zero against the row it names.
    ///
    /// Nothing needs escaping afterwards: a double quote is neither a letter nor a digit,
    /// so no word can carry one into an FTS expression.
    static func words(of text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    /// Words that say how a food was prepared or packed rather than what it is.
    ///
    /// The app's own vocabulary coming back to it: the estimation prompt asks for a food
    /// named the way a composition table names one, "saying cooked or raw where it
    /// matters", so these are the words it asked to be given. They are not food names, and
    /// a search that falls back on one of them finds whatever the table happens to have
    /// cooked — fish, for "pasta, cooked".
    ///
    /// Deliberately closed and short. It is not a stemmer or a stopword list: every entry
    /// is a word this app puts in a prompt or a composition table writes in a name.
    static let preparationWords: Set<String> = [
        "cooked", "raw", "baked", "grilled", "boiled", "fried", "roasted", "steamed",
        "fresh", "dried", "canned", "frozen", "prepacked", "prepared", "average",
    ]

    /// Whether a word says how a food was prepared rather than which food it is.
    static func isPreparationWord(_ word: String) -> Bool {
        preparationWords.contains(word.lowercased())
    }

    /// One token as an FTS5 clause: a single prefix term, or alternatives in a group.
    static func clause(for token: String) -> String {
        let terms = forms(of: token).map { "\"\($0)\"*" }
        guard terms.count > 1 else { return terms[0] }
        return "(\(terms.joined(separator: " OR ")))"
    }

    /// The forms of a token worth searching, the token itself first.
    ///
    /// Deliberately crude: dropping a trailing "s", or "es" on a longer word, and nothing
    /// cleverer. A real stemmer would need a dictionary per language and this index holds
    /// English, German and French names at once, where a wrong stem costs more than a
    /// missed one. Searching both forms is free — FTS5 unions them — so being generous
    /// here is cheap and being wrong is not.
    static func forms(of token: String) -> [String] {
        var forms = [token]
        let lowered = token.lowercased()
        if lowered.hasSuffix("es"), token.count > 4 {
            forms.append(String(token.dropLast(2)))
        }
        if lowered.hasSuffix("s"), !lowered.hasSuffix("ss"), token.count > 3 {
            let singular = String(token.dropLast())
            if !forms.contains(singular) { forms.append(singular) }
        }
        return forms
    }
}
