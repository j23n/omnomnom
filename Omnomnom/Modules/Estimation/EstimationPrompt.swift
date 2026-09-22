import Foundation

/// The instructions and the two prompt scaffolds, pure text so they are tested. The
/// instructions hold nothing the user typed: a session obeys them over the prompt, so
/// user input only ever appears inside the prompt, quoted.
nonisolated enum EstimationPrompt {
    /// Longest description that goes into a prompt; the context window is small.
    static let maximumDescriptionLength = 500

    /// The role and the rules. Name the foods, say how much was eaten, stay conservative,
    /// be honest about uncertainty, never advise, and never invent a nutrient value: the
    /// app looks those up in its own database.
    static let instructions = """
        You identify the foods in one meal for a personal food log, and how much of each was eaten. \
        Answer only with the requested structure.
        Rules:
        - List each distinct food or drink as one item.
        - name is a short plain name for the food, as the person who ate it would say it.
        - lookupTerm is the same food in the generic, unbranded wording a nutrition database uses.
        - grams is the weight of the portion that was eaten, not the package or the whole dish.
        - Never estimate energy or any nutrient value. The app looks those up in its food database.
        - Be conservative: when unsure, assume a typical portion.
        - In the note, say in one short sentence what you assumed, and say so if you are unsure.
        - Never give advice, judgment or health claims.
        """

    /// The prompt for a typed description.
    static func text(description: String) -> String {
        "List the foods in this meal and how much of each was eaten, as described by the person who ate it: \"\(clean(description))\""
    }

    /// The prompt for a photo, with the description as a hint when there is one.
    static func photoText(description: String?) -> String {
        let base = "List the foods in the meal in the attached photo and how much of each was eaten, for the portion shown."
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
