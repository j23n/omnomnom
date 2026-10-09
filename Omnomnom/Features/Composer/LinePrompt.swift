import Foundation

/// The instructions for a model that searches this device for itself, as pure text so they
/// are tested. The instructions hold nothing the user typed: a request obeys them over the
/// message, so user input only ever appears inside the message, quoted.
///
/// This is the one prompt the line path has. It replaced two — the estimation prompt that
/// asked a model to name foods, and the validation prompt that asked another to check what
/// a retriever did with those names — and both are gone now, along with the retrieval they
/// described. Two rules they had to carry are gone from this one:
///
/// - **No `lookupTerm`.** The estimation prompt spends five lines describing the shape of a
///   corpus the model cannot see — generic, unbranded, cooked or raw stated, never a dish
///   name — because it had to guess the wording a composition table uses before anything
///   was searched. A model holding the search does not guess. It looks, reads what came
///   back, and looks again under a different word if nothing fits.
/// - **No instruction about narrowing.** The old path dropped words from a term when the
///   whole term found nothing, with a rule about which words may carry the fallback,
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

    /// The two searches, by the names every driver declares them under.
    ///
    /// Here rather than in either payload because a tool's name and the sentence describing
    /// it are one decision, and the two were already drifting apart across two files: the
    /// name in one place, the words in another, and a second copy of the name beside a
    /// second copy of nothing. A model that is told to call `search_foods` and handed a tool
    /// called something else fails in a way no test of either file alone would catch.
    static let foodTool = "search_foods"
    static let productTool = "search_products"

    /// Answered to a call naming a tool this app does not have.
    ///
    /// Every call has to be answered — an unanswered one makes the next request invalid on
    /// at least one of the two wire protocols — so a wrong name gets a sentence pointing at
    /// the right one rather than silence. The on-device driver answers it too, where the
    /// case it covers is a product search called with its opt-in off.
    static let noSuchSearch = "There is no such search. Use \(foodTool)."

    /// How many round trips one line may take before the app gives up.
    ///
    /// Enough for a model to search for every food, read the results and search again for
    /// the ones that found nothing; small enough that a model which will not stop searching
    /// costs a bounded number of requests rather than a bill. One number for both drivers
    /// that count, because it is a judgment about how a model behaves and not about whose
    /// server it is running on.
    ///
    /// It does not reach the on-device driver, which does not write the conversation and so
    /// never gets to stop it — the framework decides there, and that path is unbounded.
    /// `docs/OPEN-QUESTIONS.md` holds what to do about it.
    static let maximumRounds = 5

    /// Said when the model is still searching after `maximumRounds`. Shared verbatim by the
    /// two drivers that can say it: the words name the model rather than the endpoint, so
    /// there is nothing per-path in them.
    static let keptSearching = "the model kept searching without answering. Try again, or describe the meal more plainly."

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

    /// Longest line that goes into a prompt, matching the estimator's own bound.
    static let maximumLineLength = 500

    /// Trimmed, newlines collapsed, capped, and quotation marks neutralised so a typed one
    /// cannot close the one the message wraps it in.
    ///
    /// What a line may carry into a prompt is one decision. This was the validation
    /// prompt's, and every caller delegated to it; the prompt is gone and the decision is
    /// not, so it lives here, where the line that reaches a model is built.
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
