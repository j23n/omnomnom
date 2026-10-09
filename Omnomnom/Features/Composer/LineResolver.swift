import Foundation
import SwiftData
import os

/// Turning what someone wrote, or photographed, into rows that can be logged.
///
/// Two things are tried, in this order, and the order is the whole design:
///
/// 1. **Phrase recall.** The whole line has been logged before, so every food and every
///    amount comes back from the last time. Nothing is asked of a model at all — which is
///    what keeps a repeat under five seconds and is why it stays in front.
/// 2. **A model that searches this device for itself.** It decides what to look for, reads
///    the rows that came back, and looks again under different wording until it answers.
///    It never supplies a nutrient value: it says *which* rows, and the database says what
///    is in them.
///
/// Neither is checked by a second model pass. Recall needs none — the user already
/// asserted it — and the driving model chose from rows it was shown, so there is nothing
/// for a checker to tell it that it did not already see.
///
/// What used to be here instead was a ladder: a model named the foods and guessed at the
/// wording a composition table uses, the app searched on that guess, arbitrated between
/// the tables and Open Food Facts, dropped words from the term when nothing answered, and
/// then spent a second request asking a model to check what its own retriever had done.
/// Every rung of that existed because the model could not see the database. One that can
/// search needs none of them, so the guess, the arbitration, the word-dropping and the
/// checker went together. The search itself stays, as `candidates(for:)`, because the
/// sheet still offers the other foods a row could have been.
///
/// Without a model nothing new resolves, so a line resolves to nothing and the composer says
/// so. That is the price of one primary input: search and the barcode scanner are how the
/// app is used when no model will answer.
///
/// Main-actor because recall and `FoodChoice` construction read a `ModelContext`; the
/// search and the model are awaited into their own actors.
struct LineResolver {
    let context: ModelContext
    let repository: any FoodSearching
    /// A model that searches this device for itself. `nil` when the estimation opt-in is
    /// off or no provider will answer, in which case nothing new can be resolved and only
    /// a line logged before comes back. See `LineResolver+Tools`.
    let driver: (any LineDriving)?

    init(
        context: ModelContext,
        repository: any FoodSearching,
        driver: (any LineDriving)? = nil
    ) {
        self.context = context
        self.repository = repository
        self.driver = driver
    }

    /// Whether anything at all can read a line the app has not seen before.
    var canReadALine: Bool { driver != nil }

    /// The resolver as the app wires it, from the two opt-ins that govern it.
    ///
    /// `estimationEnabled` is the Meal estimation toggle, and it gates the model: with it
    /// off nothing is asked of anything, and a line that has never been logged resolves to
    /// nothing. It used to gate only the second validating request, which meant the toggle
    /// did not govern the request that actually sent the line — the one thing a reader of
    /// that switch would expect it to.
    ///
    /// The searches are built either way, because they cost nothing to build and
    /// `Estimators.driver` is the single place that reads which provider was chosen. The
    /// product search is the second opt-in: with it off the product tool is not declared
    /// at all, which is not the same as a tool that answers nothing — an undeclared tool
    /// cannot be called, so the model never spends a round trip finding it empty.
    static func app(
        context: ModelContext,
        repository: FoodRepository,
        estimationEnabled: Bool,
        productSearchEnabled: Bool
    ) -> LineResolver {
        let searcher = AppLineSearch.app(
            repository: repository, productSearchEnabled: productSearchEnabled
        )
        return LineResolver(
            context: context,
            repository: repository,
            driver: estimationEnabled ? Estimators.driver(searching: searcher) : nil
        )
    }

    /// A typed line, resolved.
    func resolve(_ line: String) async -> LineResolution {
        await resolve(.text(line), line: line)
    }

    /// The foods a word could have meant, best first. What a row offers when the user
    /// questions the food it was given.
    ///
    /// This is the only caller of the search below, and the reason all of it survived the
    /// ladder: head phrase, word combinations and the rule about which words may carry a
    /// fallback are what make a short list of alternatives worth reading rather than a
    /// page of rows that happen to share a word.
    ///
    /// It is not the search the row itself came from, and cannot be. A driving model
    /// chooses its own terms, so the rows it saw are the ones it asked for; this asks the
    /// one question the user is actually posing — what else could this word have meant —
    /// and answers it from the same tables. Nothing is checked by a model: the person is
    /// reading the list themselves, which is the whole point of offering it.
    func candidates(for term: String) async -> [FoodChoice] {
        await search(term).map { remembered(FoodChoice(bundled: $0.food)) }
    }

    /// What someone wrote or photographed, resolved. Never throws: a failure anywhere
    /// leaves rows unmatched for the user to settle, which is a worse outcome than a good
    /// match and a far better one than an error where a meal should be.
    ///
    /// `line` is what the sheet shows and what a phrase is remembered under. For a photo it
    /// is whatever words came with it, which may be nothing — a picture with no description
    /// resolves, but there is no line to remember it by.
    func resolve(_ input: EstimationInput, line: String) async -> LineResolution {
        if case .text = input, let recalled = recallWholeLine(line) {
            return recalled
        }
        guard let driver else {
            AppLog.estimation.info("no model configured; nothing to resolve")
            return LineResolution(line: line, rows: [], wasChecked: false)
        }
        return await resolve(input, line: line, driving: driver)
    }

    /// What to put in front of the user when a model failed, or `nil` where there is
    /// nothing to say.
    ///
    /// Every one of these sentences names something the user can go and fix — a refused
    /// key, an address that cannot be reached, a request the API rejected and quoted the
    /// field of. Saying "nothing in that looked like a food" instead sends someone back to
    /// rewrite a line that was fine, which is the one thing the composer's own copy rules
    /// out elsewhere.
    ///
    /// Cancellation is the exception: the user typed on, the answer is about a line they
    /// have moved past, and there is nothing for them to do.
    static func sentence(for error: any Error) -> String? {
        let mapped = EstimationError.map(error)
        guard mapped != .cancelled else { return nil }
        return mapped.errorDescription
    }

    // MARK: - What the user already asserted

    /// The whole line from memory, or `nil` when it has never been logged.
    private func recallWholeLine(_ line: String) -> LineResolution? {
        guard let phrase = try? Phrase.recall(line, in: context),
              let resolution = resolution(for: phrase, line: line)
        else { return nil }
        phrase.noteRecalled()
        AppLog.store.info("recalled a phrase of \(resolution.rows.count) items")
        return resolution
    }

    /// What a remembered phrase comes to, without going through a typed line.
    ///
    /// Used by recall above and by accepting a day's baseline, which is the same act with
    /// no typing in front of it. `nil` when any item no longer resolves: half a meal
    /// returned silently is worse than being asked again.
    func resolution(for phrase: Phrase, line: String? = nil) -> LineResolution? {
        let items = phrase.orderedItems
        let rows = items.compactMap { item -> ResolvedRow? in
            guard let choice = choice(for: item) else { return nil }
            return ResolvedRow(
                name: item.name,
                choice: choice,
                amount: item.amount,
                bucket: .usual,
                // A line that came back from memory is history by definition, so the
                // amount it brought back is what a step measures from.
                baseAmount: item.amount,
                origin: .phrase,
                confidence: .settled
            )
        }
        guard rows.count == items.count, !rows.isEmpty else { return nil }
        return LineResolution(line: line ?? phrase.text, rows: rows, wasChecked: false)
    }

    // MARK: - What the database says

    /// How many rows one search answers with, which is what the sheet offers as the other
    /// foods a row could have been. Six fitted a prompt; it fits a list for the same
    /// reason, which is that a person reading alternatives wants a few good ones.
    static let candidatesPerTerm = 6

    /// The shortlist for one named food, with one fallback.
    ///
    /// The index ands a term's words together, so a term naming a food precisely can reach
    /// nothing at all: "rolled oats" wants a row holding both words and the tables hold
    /// "Oat flakes"; "chicken breast cooked" wants three and no row has them. When the whole
    /// term finds nothing worth showing, each of its words is tried alone and the best
    /// answer kept — "oats" finds the flakes, "chicken" finds the chicken.
    ///
    /// Only then, though. A term that matches something specific keeps it: "minced beef"
    /// reaching minced steak is better than "beef" reaching plain boiled beef, even though
    /// the plainer row scores higher for being shorter and more popular. Specificity wins
    /// where it works; breadth only rescues a dead end.
    ///
    /// **A preparation word never carries the fallback.** Measured against the real tables,
    /// the version without this rule answered "Pasta, cooked" and "Rice, cooked" with *Fish,
    /// cooked (average)*, settled, unasked — the word "cooked" names 390 rows and the
    /// cooked thing it ranked highest happened to be fish. "Oats, rolled" reached a rolled
    /// pork roast the same way. A word saying how a food was prepared is not a food, and
    /// there is no honest way to answer a term from one.
    private func search(_ term: String) async -> [FoodMatch] {
        guard !term.isEmpty else { return [] }
        let whole = await shortlist(for: term, scoredAgainst: term)
        if let best = whole.first, best.score >= FoodMatcher.probableAt {
            return whole
        }

        // Only the head phrase, and only combinations of it. Trying every word of the
        // term was measured against a hundred lines and was wrong far more often than it
        // was right: a term's qualifiers score perfectly against rows that are a
        // different food, so "yogurt, natural" answered with *Natural mineral water* and
        // "baked beans in tomato sauce" with *Tomato raw*. Both scored above the settled
        // line. The head phrase cannot do that, and when it finds nothing the row blocks
        // and asks — which is the honest answer and the one the sheet is built for.
        let words = FoodQuery.words(of: term)
        let phrase = FoodQuery.headPhrase(of: term)
        guard words.count > 1, !phrase.isEmpty else {
            return whole
        }

        var best = whole
        for indices in Self.subsets(of: phrase.count) {
            // The phrase entire, where that is the whole term, is what was just tried.
            if indices.count == phrase.count, phrase.count == words.count { continue }
            let combination = indices.map { phrase[$0] }
            let sub = combination.joined(separator: " ")
            let candidates = await shortlist(for: sub, scoredAgainst: sub)
                .filter { match in
                    combination.contains { FoodMatcher.answersHead(match.food.name, with: $0) }
                }
            if let top = candidates.first, top.score > (best.first?.score ?? 0) {
                best = candidates
            }
        }
        return best
    }

    /// Every non-empty subset of `0..<count`, the largest first and each in ascending
    /// order, so which combination wins a tie is fixed rather than incidental.
    private static func subsets(of count: Int) -> [[Int]] {
        guard count > 0, count < 16 else { return [] }
        var subsets: [[Int]] = []
        for size in stride(from: count, through: 1, by: -1) {
            for mask in 1..<(1 << count) where mask.nonzeroBitCount == size {
                subsets.append((0..<count).filter { mask & (1 << $0) != 0 })
            }
        }
        return subsets
    }

    /// One search, ranked. `scoredAgainst` is what the scorer compares a row to, which is
    /// not always what was searched for: a fallback searches one word and must then be
    /// ranked by that word, or every row would score as a partial match of the whole term.
    private func shortlist(for term: String, scoredAgainst scoring: String) async -> [FoodMatch] {
        do {
            return FoodMatcher.shortlist(
                try await repository.search(term), term: scoring,
                limit: Self.candidatesPerTerm
            )
        } catch {
            AppLog.foodDB.error("line lookup failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    /// The same choice, with what this person last had of that food filled in.
    ///
    /// A search hit knows nothing of past use: `FoodChoice(bundled:)` is built from the
    /// table row alone, so its `lastAmount` is always nil. The history is in the stored
    /// `Food`, which the Quantity sheet has always read and the line path did not — so a
    /// food logged ten times through search arrived with no reference, and the row offered
    /// no Less or More. The steps are meant to arrive once a food has been eaten once, not
    /// once it has been recalled as a phrase.
    ///
    /// The amount is untouched. The reference is what this person usually has; the amount
    /// is what the model says was eaten today, and those are different questions.
    ///
    /// Internal rather than private because two callers owe a row its reference: the
    /// alternatives above, and the driving path in `LineResolver+Tools` for a row the model
    /// chose. Two copies of this lookup would be two places for it to go missing.
    func remembered(_ choice: FoodChoice) -> FoodChoice {
        guard let id = choice.bundledID else { return choice }
        do {
            guard let food = try Food.bundled(id: id, in: context) else { return choice }
            return choice.with(lastAmount: food.lastGrams)
        } catch {
            AppLog.store.error("stored food lookup failed: \(error.localizedDescription, privacy: .public)")
            return choice
        }
    }

    // MARK: - Reading a stored item back

    /// The choice behind a remembered item, or `nil` when what it pointed at is gone.
    private func choice(for item: PhraseItem) -> FoodChoice? {
        if let recipe = item.recipe { return recipe.choice }
        return item.food.flatMap(\.choice)
    }
}
