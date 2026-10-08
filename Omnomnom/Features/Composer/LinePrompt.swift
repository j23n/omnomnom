import Foundation

/// The instructions for a model that searches this device for itself, as pure text so they
/// are tested. The instructions hold nothing the user typed: a request obeys them over the
/// message, so user input only ever appears inside the message, quoted.
///
/// This is `EstimationPrompt` and `ValidationPrompt` collapsed into one, which is the whole
/// point of the path. Two rules that had to be in those prompts are gone from this one:
///
/// - **No `lookupTerm`.** The estimation prompt spends five lines describing the shape of a
///   corpus the model cannot see — generic, unbranded, cooked or raw stated, never a dish
///   name — because it had to guess the wording a composition table uses before anything
///   was searched. A model holding the search does not guess. It looks, reads what came
///   back, and looks again under a different word if nothing fits.
/// - **No instruction about narrowing.** `LineResolver` drops words from a term when the
///   whole term finds nothing, with a rule about which words may carry the fallback,
///   because the retriever had one chance at the wording. Searching again is a cheaper and
///   more honest version of the same recovery, and it is the model's to decide.
///
/// What is kept verbatim in spirit is the line the whole design rests on: the model says
/// which foods, and the database says what is in them.
nonisolated enum LinePrompt {
    static let instructions = """
        You turn one meal, described or photographed, into rows of a personal food log. \
        You search this person's own food database and choose rows from it. \
        Answer only with the requested structure.
        How to work:
        - Decide which distinct foods and drinks the meal holds. When it is named as a dish \
        rather than described, that is the foods the dish is made of: "spaghetti bolognese" \
        is pasta, minced beef, tomato, onion and olive oil.
        - Keep it to the few foods that carry the meal. Leave out a pinch of salt or a sprig \
        of herbs: they weigh nothing and cost the person a decision each.
        - Search for each food before you answer. You may search more than once for the same \
        food: the database is a nutrition composition table, so it words things its own way, \
        and a word that finds nothing is worth trying again differently rather than guessing. \
        Search for several foods at once where you can.
        - Choose the candidate that is the food this person actually ate, by its id.
        - Prefer the form a person eats. A drink is not its powder, a cooked food is not its \
        raw row, a food is not a dry concentrate of itself. A candidate marked as an \
        ingredient or dry form is rarely what was eaten.
        - Energy per 100 g is given so you can tell those apart. Never report it, never \
        calculate with it, and never state any nutrient value: the app reads every figure \
        from the row you choose.
        - Answer 0 for a food neither search holds. That is a correct answer and the person \
        is asked; a row that is nearly right is worse than no row.
        - grams is the weight of the portion eaten, not the package or the whole dish.
        - Be conservative: when unsure, assume a typical portion.
        - Say certain only when the choice is plainly right, probable when it is likely, and \
        unsure when you would be guessing.
        - Set implausible only when the amount and the chosen food do not go together, such \
        as 200 g of a powder or two kilos of butter.
        - In the note, say in one short sentence what you assumed, and say so if you are \
        unsure.
        - Never give advice, judgment or health claims.
        """

    /// What the food search is for, as the model reads it.
    static let foodToolDescription = """
        Search this device's bundled nutrition composition tables for a food. These are \
        generic, measured, unbranded foods. Returns candidate rows with an id, a name, a \
        category, energy per 100 g, and whether a row is an ingredient or dry form. Call it \
        once per wording you want to try.
        """

    /// What the product search is for. Only declared when the opt-in is on, so the words
    /// "leaves the device" are true wherever the model can read them.
    static let productToolDescription = """
        Search Open Food Facts for a branded product by name. Use it for a packaged or \
        branded food, which the bundled tables never hold. The search term leaves the \
        device. The records are crowdsourced, so a row may be short of some figures; the \
        result says how many.
        """

    /// The message for a typed line.
    static func text(line: String) -> String {
        "Turn this meal into rows, as described by the person who ate it: \"\(clean(line))\""
    }

    /// The message for a photo, with whatever words came with it.
    static func photo(line: String?) -> String {
        let base = "Turn the meal in the attached photo into rows, for the portion shown."
        let hint = line.map(clean) ?? ""
        guard !hint.isEmpty else { return base }
        return "\(base) The person who ate it says: \"\(hint)\""
    }

    /// One search's hits, as the result the model reads. Empty is said rather than left
    /// blank: "nothing" is information worth acting on, and a blank result invites a model
    /// to assume the call failed and repeat it.
    static func results(_ candidates: [LineCandidate]) -> String {
        guard !candidates.isEmpty else { return "No rows match that. Try different wording." }
        return candidates.map(\.promptLine).joined(separator: "\n")
    }

    /// Trimmed, newlines collapsed, capped, and quotation marks neutralised so a typed one
    /// cannot close the one the message wraps it in.
    ///
    /// The validation prompt's own cleaning, cap included, rather than a second copy of it:
    /// what a line may carry into a prompt is one decision, and two of them would drift.
    static func clean(_ text: String) -> String {
        ValidationPrompt.clean(text)
    }
}
