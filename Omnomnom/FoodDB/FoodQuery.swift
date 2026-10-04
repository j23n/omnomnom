import Foundation

/// Builds FTS5 MATCH expressions. Pure and tested.
nonisolated enum FoodQuery {
    /// Turns free text into an FTS5 expression: each whitespace-separated token is
    /// double-quoted (internal quotes doubled) and prefix-matched with `*`.
    /// Returns `nil` when the text holds no tokens.
    ///
    /// A token that looks like a plural is searched in both forms, because FTS5's prefix
    /// match only works forwards. `"oat"*` finds "Oat flakes"; `"oats"*` finds nothing at
    /// all, and the German table calls the food "Oat flakes". Typing the plural of a food
    /// is not an unusual thing to do, so without this the most ordinary breakfast in the
    /// database is unreachable — which is how it was found.
    static func ftsMatchExpression(for text: String) -> String? {
        let tokens = text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        // Joined with an explicit AND rather than a space. FTS5's implicit AND does not
        // accept a parenthesised group beside a bare term — `"oat"* ("flakes"* OR
        // "flake"*)` is a syntax error — and spelling the operator out is valid in every
        // combination. Found by running the expressions against the real index.
        return tokens.map(clause(for:)).joined(separator: " AND ")
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
