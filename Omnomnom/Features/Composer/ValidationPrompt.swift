import Foundation

/// The instructions and the prompt for checking a match, as pure text so they are tested.
///
/// The instructions hold nothing the user typed: a session obeys them over the prompt,
/// so user input only ever appears inside the prompt, quoted.
///
/// What the model is asked for is a choice among rows a retriever already found, which
/// is the one thing here it is better at than a text search. It is never asked what a
/// food contains.
nonisolated enum ValidationPrompt {
    /// Candidates offered per item. Enough for a real choice, small enough that a whole
    /// line of items fits the window with room to spare.
    static let candidatesPerItem = 6

    /// Longest line that goes into a prompt, matching the estimator's own bound.
    static let maximumLineLength = 500

    static let instructions = """
        You match foods from a person's food log against rows of a nutrition database. \
        Answer only with the requested structure.
        Rules:
        - For each item, choose the candidate that is the food the person actually ate.
        - Answer with the candidate's id. Answer 0 when none of the candidates is that food.
        - Prefer the form a person eats. A drink is not its powder, a cooked food is not \
        its raw row, a food is not a dry concentrate of itself.
        - Energy per 100 g is given so you can tell those apart. Never report it, never \
        calculate with it, and never state any nutrient value: the app reads those from \
        the row you choose.
        - Say certain only when the choice is plainly right, probable when it is likely, \
        and unsure when you would be guessing.
        - Set implausible only when the amount eaten and the chosen food do not go \
        together, such as 200 g of a powder or two kilos of butter.
        - Never give advice, judgment or health claims.
        """

    /// The prompt for one line: what was eaten, then the items and their candidates.
    ///
    /// Items are numbered from 1 and candidates are named by their real database id, so
    /// a verdict needs no mapping back and an id outside the list cannot be mistaken for
    /// a choice.
    static func text(line: String, items: [ValidationItem]) -> String {
        var parts = [
            "The person wrote: \"\(clean(line))\"",
            "Choose a database row for each item.",
        ]
        for item in items {
            parts.append(describe(item))
        }
        return parts.joined(separator: "\n")
    }

    /// One item and its candidates, as the prompt lists them.
    static func describe(_ item: ValidationItem) -> String {
        var lines = ["Item \(item.number): \"\(clean(item.name))\", \(item.amountText)"]
        for candidate in item.candidates {
            lines.append("  id \(candidate.id): \(clean(candidate.name))\(candidate.detail)")
        }
        if item.candidates.isEmpty {
            lines.append("  no candidates")
        }
        return lines.joined(separator: "\n")
    }

    /// Trimmed, newlines collapsed, capped, and quotes neutralised so a typed quotation
    /// mark cannot close the one the prompt wraps it in.
    static func clean(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\"", with: "'")
        return String(collapsed.prefix(maximumLineLength))
    }
}

/// One item as the prompt sees it: its number, what it was called, how much of it, and
/// the rows the retriever found.
nonisolated struct ValidationItem: Hashable, Sendable {
    let number: Int
    let name: String
    /// How much was eaten, already in words: "about 40 g", "1 serving".
    let amountText: String
    let candidates: [ValidationCandidate]
}

/// One candidate row, reduced to what a choice can be made on.
///
/// Energy is included because it is what tells a drink from its powder, and the
/// instructions forbid repeating or calculating with it.
nonisolated struct ValidationCandidate: Hashable, Sendable {
    let id: Int
    let name: String
    let category: String?
    let energy: Double?

    /// The parenthetical after the name, empty when neither figure is known.
    var detail: String {
        var bits: [String] = []
        if let category, !category.isEmpty { bits.append(category) }
        if let energy { bits.append("\(Int(energy.rounded())) kcal/100 g") }
        return bits.isEmpty ? "" : " (\(bits.joined(separator: ", ")))"
    }
}
