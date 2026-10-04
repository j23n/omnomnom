import Foundation

/// The instructions and the two prompt scaffolds, pure text so they are tested. The
/// instructions hold nothing the user typed: a session obeys them over the prompt, so
/// user input only ever appears inside the prompt, quoted.
nonisolated enum EstimationPrompt {
    /// Longest description that goes into a prompt; the context window is small.
    static let maximumDescriptionLength = 500

    /// The role and the rules.
    ///
    /// Two of these rules are here because of one meal. "Spaghetti bolognese" was answered
    /// with two items, "spaghetti" and "bolognese", which is what "each distinct food" says
    /// to do if a dish's name is read as a list of foods. Neither reached anything: the
    /// bundled tables hold no row called spaghetti — the nearest is spaghetti *squash*, a
    /// vegetable at 32 kcal — and bolognese alone is a sauce rather than the meal.
    ///
    /// So a dish named rather than described has to be broken into what it is made of, and
    /// `lookupTerm` has to be the name of a staple as a composition table writes it. The
    /// model cannot see the database, so the rules describe the shape of what is in it:
    /// generic foods, cooked or raw stated, no dish names and no brands.
    static let instructions = """
        You identify the foods in one meal for a personal food log, and how much of each was eaten. \
        Answer only with the requested structure.
        Rules:
        - List each distinct food or drink as one item.
        - When the meal is named as a dish rather than described, list the foods that dish is \
        made of, not the words of its name. "Spaghetti bolognese" is pasta, minced beef, \
        tomato, onion and olive oil. "Chicken curry with rice" is rice, chicken, curry sauce.
        - Keep it to the few foods that carry the meal. Leave out a pinch of salt or a sprig \
        of herbs: they weigh nothing and cost the person a decision each.
        - name is a short plain name for the food, as the person who ate it would say it.
        - lookupTerm is a staple food named the way a nutrition composition table names one: \
        generic, unbranded, and saying cooked or raw where it matters. "Pasta, cooked", not \
        "spaghetti". "Minced beef", not "bolognese". "Tomato puree", not "ragu". Never a dish \
        name, a brand or a recipe in this field.
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
