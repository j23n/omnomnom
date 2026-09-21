import Foundation

/// Builds FTS5 MATCH expressions. Pure and tested.
nonisolated enum FoodQuery {
    /// Turns free text into an FTS5 expression: each whitespace-separated token is
    /// double-quoted (internal quotes doubled) and prefix-matched with `*`.
    /// Returns `nil` when the text holds no tokens.
    static func ftsMatchExpression(for text: String) -> String? {
        let tokens = text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
