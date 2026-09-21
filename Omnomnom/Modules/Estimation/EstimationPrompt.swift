import Foundation

/// The instructions and the two prompt scaffolds, pure text so they are tested. The
/// instructions hold nothing the user typed: a session obeys them over the prompt, so
/// user input only ever appears inside the prompt, quoted.
nonisolated enum EstimationPrompt {
    /// Longest description that goes into a prompt; the context window is small.
    static let maximumDescriptionLength = 500

    /// The role and the rules. Conservative, totals for the portion eaten, sodium in
    /// milligrams, honest about uncertainty, and never advice.
    static let instructions = """
        You estimate the nutrition of one meal for a personal food log. \
        Answer only with the requested structure.
        Rules:
        - List each distinct food or drink as one item with a short plain name.
        - grams is the weight of the portion that was eaten, not the package or the whole dish.
        - Every nutrient value is the total for that portion, not per 100 g.
        - Energy in kcal; protein, carbohydrates, fat, saturated fat, fiber and sugar in grams; sodium in milligrams.
        - Be conservative: when unsure, assume a typical portion and typical values.
        - In the note, say in one short sentence what you assumed, and say so if you are unsure.
        - Never give advice, judgment or health claims.
        """

    /// The prompt for a typed description.
    static func text(description: String) -> String {
        "Estimate the nutrition of this meal, described by the person who ate it: \"\(clean(description))\""
    }

    /// The prompt for a photo, with the description as a hint when there is one.
    static func photoText(description: String?) -> String {
        let base = "Estimate the nutrition of the meal in the attached photo, for the portion shown."
        let hint = description.map(clean) ?? ""
        guard !hint.isEmpty else { return base }
        return "\(base) The person who ate it says: \"\(hint)\""
    }

    /// Trimmed, newlines collapsed, capped at `maximumDescriptionLength`.
    static func clean(_ description: String) -> String {
        let collapsed = description
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(maximumDescriptionLength))
    }
}
