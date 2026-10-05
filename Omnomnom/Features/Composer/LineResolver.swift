import Foundation
import SwiftData
import os

/// One food to resolve: what to call it, what to look it up as, and what the model
/// thought was eaten.
///
/// This used to be a `ParsedItem`, cut out of the line by a hand-written parser that split
/// on commas and read a quantity off the front of each part. The parser is gone. It could
/// not tell "yogurt with bananas" from "spaghetti bolognese" without a rule that was wrong
/// for one of them, and a model that names a dish's parts needs no rule at all.
nonisolated struct ResolvableItem: Identifiable, Hashable, Sendable {
    let id: UUID
    /// What the person who ate it would call it, which is what the row shows.
    let name: String
    /// The same food in the wording a composition table uses, which is what is searched.
    let lookupTerm: String
    /// What the model estimated was eaten, in the food's own unit.
    let estimated: Double

    init(id: UUID = UUID(), name: String, lookupTerm: String, estimated: Double) {
        self.id = id
        self.name = name
        self.lookupTerm = lookupTerm
        self.estimated = estimated
    }

    /// The items of an estimate, after it has been clamped and trimmed.
    static func items(of estimate: MealEstimate) -> [ResolvableItem] {
        EstimateConversion.convert(estimate).items.map {
            ResolvableItem(name: $0.name, lookupTerm: $0.lookupTerm, estimated: $0.grams)
        }
    }
}

/// Turning what someone wrote, or photographed, into rows that can be logged.
///
/// Four rungs, tried in order, and the order is the whole design:
///
/// 1. **Phrase recall.** The whole line has been logged before, so every food and every
///    amount comes back from the last time. Nothing is asked of a model at all — which is
///    what keeps a repeat under five seconds and is why it stays in front.
/// 2. **The model**, which names the foods in what was written and estimates a weight for
///    each. It never supplies a nutrient value: it says *which* foods, and the database
///    says what is in them.
/// 3. **The bundled tables**, through FTS5 and `FoodMatcher`, once per named food.
/// 4. **Open Food Facts**, when the product opt-in is on and the tables held nothing.
///
/// Rung 1 is not checked: the user already asserted it. Rungs 3 and 4 are checked by a
/// second model pass where there is a model, which is what moves "oats" off an oat biscuit.
///
/// Without a model there is no rung 2, so a line resolves to nothing and the composer says
/// so. That is the price of one primary input: search and the barcode scanner are how the
/// app is used when no model will answer.
///
/// Main-actor because recall and `FoodChoice` construction read a `ModelContext`; the
/// estimate, the search and the validation are awaited into their own actors.
struct LineResolver {
    let context: ModelContext
    let repository: any FoodSearching
    /// `nil` where Apple Intelligence is unavailable, which is an ordinary configuration
    /// rather than a failure: the line still resolves, fewer rows settle, and the sheet
    /// says what it did instead of apologising for what it could not.
    let validator: (any MatchValidating)?
    /// Looked up when the bundled tables answer nothing, and only when the user has
    /// turned product search on.
    let products: ((String) async -> [FoodChoice])?
    /// Names the foods in what was written. `nil` when neither Apple Intelligence nor an
    /// endpoint of the user's own will answer, in which case nothing new can be resolved
    /// and only a line logged before comes back.
    let estimator: (any MealEstimating)?

    init(
        context: ModelContext,
        repository: any FoodSearching,
        validator: (any MatchValidating)? = nil,
        products: ((String) async -> [FoodChoice])? = nil,
        estimator: (any MealEstimating)? = nil
    ) {
        self.context = context
        self.repository = repository
        self.estimator = estimator
        self.validator = validator
        self.products = products
    }

    /// A typed line, resolved.
    func resolve(_ line: String) async -> LineResolution {
        await resolve(.text(line), line: line)
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
        guard let estimate = await estimate(input) else {
            return LineResolution(line: line, rows: [], wasChecked: false)
        }
        let items = ResolvableItem.items(of: estimate)
        guard !items.isEmpty else {
            return LineResolution(line: line, rows: [], wasChecked: false)
        }

        var rows: [ResolvedRow] = []
        var shortlists: [UUID: [FoodMatch]] = [:]
        for item in items {
            if let row = recallItem(item) {
                rows.append(row)
                continue
            }
            let shortlist = await search(item.lookupTerm)
            shortlists[item.id] = shortlist
            rows.append(await databaseRow(for: item, shortlist: shortlist))
        }

        // One request for the whole line, and only for the rows a retriever chose.
        let checked = await check(line: line, items: items, shortlists: shortlists, rows: &rows)
        return LineResolution(
            line: line, rows: rows, wasChecked: checked, meal: estimate.meal.slot
        )
    }

    /// What the model made of the input, or `nil` when none would answer.
    ///
    /// A failure is logged and swallowed. The composer shows an empty resolution the same
    /// way it shows a line with no food in it, because from the user's side those are the
    /// same situation: nothing to sign off, and the other ways in are still there.
    private func estimate(_ input: EstimationInput) async -> MealEstimate? {
        guard let estimator else {
            AppLog.estimation.info("no estimator configured; nothing to resolve")
            return nil
        }
        do {
            return try await estimator.estimate(input)
        } catch {
            AppLog.estimation.info("estimate failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Rung one and two: what the user already asserted

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

    /// One named food from memory, or `nil` when it has no record.
    private func recallItem(_ item: ResolvableItem) -> ResolvedRow? {
        guard let key = PhraseKey.normalise(item.lookupTerm),
              let phrase = try? Phrase.recall(key: key, in: context),
              let stored = phrase.orderedItems.first,
              phrase.orderedItems.count == 1,
              let choice = choice(for: stored)
        else { return nil }
        return ResolvedRow(
            id: item.id,
            name: item.name,
            choice: choice,
            // The estimate is what was said about today; the stored amount is what this
            // person usually has. The first is logged, the second is what a step measures
            // from — so saying "a big bowl" is honoured, and "less" afterwards still means
            // less than usual rather than less than big.
            amount: item.estimated,
            bucket: nil,
            baseAmount: stored.amount,
            origin: .item,
            confidence: .settled
        )
    }

    // MARK: - Rung three and four: what the database says

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
    private func search(_ term: String) async -> [FoodMatch] {
        guard !term.isEmpty else { return [] }
        let whole = await shortlist(for: term, scoredAgainst: term)
        if let best = whole.first, best.score >= FoodMatcher.probableAt { return whole }

        let tokens = term.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 1 else { return whole }
        var best = whole
        for token in tokens {
            let candidates = await shortlist(for: token, scoredAgainst: token)
            if let top = candidates.first, top.score > (best.first?.score ?? 0) {
                best = candidates
            }
        }
        return best
    }

    /// One search, ranked. `scoredAgainst` is what the scorer compares a row to, which is
    /// not always what was searched for: a fallback searches one word and must then be
    /// ranked by that word, or every row would score as a partial match of the whole term.
    private func shortlist(for term: String, scoredAgainst scoring: String) async -> [FoodMatch] {
        do {
            return FoodMatcher.shortlist(
                try await repository.search(term), term: scoring,
                limit: ValidationPrompt.candidatesPerItem
            )
        } catch {
            AppLog.foodDB.error("line lookup failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    /// A row from the best match, falling back to a product when the tables held nothing.
    private func databaseRow(for item: ResolvableItem, shortlist: [FoodMatch]) async -> ResolvedRow {
        if let best = shortlist.first {
            let choice = remembered(FoodChoice(bundled: best.food))
            return ResolvedRow(
                id: item.id,
                name: item.name,
                choice: choice,
                amount: item.estimated,
                bucket: nil,
                baseAmount: choice.lastAmount,
                origin: .database,
                confidence: best.confidence
            )
        }
        if let products, let product = await products(item.lookupTerm).first {
            return ResolvedRow(
                id: item.id,
                name: item.name,
                choice: product,
                amount: item.estimated,
                bucket: nil,
                baseAmount: product.lastAmount,
                origin: .product,
                confidence: .probable
            )
        }
        return ResolvedRow(
            id: item.id, name: item.name, choice: nil, amount: 0,
            origin: .database, confidence: .unsure
        )
    }

    /// The same choice, with what this person last had of that food filled in.
    ///
    /// A search hit knows nothing of past use: `FoodChoice(bundled:)` is built from the
    /// table row alone, so its `lastAmount` is always nil. The history is in the stored
    /// `Food`, which the Quantity sheet has always read and this path did not — so a food
    /// logged ten times through search still arrived here with no reference, and the row
    /// offered no Less or More. The steps are meant to arrive once a food has been eaten
    /// once, not once it has been recalled as a phrase.
    ///
    /// The amount is untouched. The reference is what this person usually has; the amount
    /// is what the model says was eaten today, and those are different questions.
    private func remembered(_ choice: FoodChoice) -> FoodChoice {
        guard let id = choice.bundledID else { return choice }
        do {
            guard let food = try Food.bundled(id: id, in: context) else { return choice }
            return choice.with(lastAmount: food.lastGrams)
        } catch {
            AppLog.store.error("stored food lookup failed: \(error.localizedDescription, privacy: .public)")
            return choice
        }
    }

    // MARK: - Checking

    /// Asks the model to choose among the rows a retriever found, and applies what it
    /// says. Returns whether the line was checked at all.
    ///
    /// All-or-nothing: a validator that throws, is cancelled or answers short leaves the
    /// whole line unchecked rather than some rows checked and others not.
    private func check(
        line: String, items resolvable: [ResolvableItem], shortlists: [UUID: [FoodMatch]],
        rows: inout [ResolvedRow]
    ) async -> Bool {
        guard let validator, !shortlists.isEmpty else { return false }
        var items: [ValidationItem] = []
        var itemRows: [Int: Int] = [:]
        var itemMatches: [Int: [FoodMatch]] = [:]
        for item in resolvable {
            guard let shortlist = shortlists[item.id], !shortlist.isEmpty,
                  let rowIndex = rows.firstIndex(where: { $0.id == item.id })
            else { continue }
            let number = items.count + 1
            itemRows[number] = rowIndex
            itemMatches[number] = shortlist
            items.append(
                ValidationItem(
                    number: number,
                    name: item.name,
                    amountText: amountText(rows[rowIndex]),
                    candidates: shortlist.map {
                        ValidationCandidate(
                            id: $0.food.id, name: $0.food.name,
                            category: $0.food.category, energy: $0.food.per100g.energy
                        )
                    }
                )
            )
        }
        guard !items.isEmpty else { return false }

        let verdicts: MatchVerdicts
        do {
            verdicts = try await validator.validate(line: line, items: items)
        } catch {
            AppLog.estimation.info("line left unchecked: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard verdicts.verdicts.count == items.count else {
            AppLog.estimation.info("validation answered \(verdicts.verdicts.count) of \(items.count); line left unchecked")
            return false
        }
        for item in items {
            guard let verdict = verdicts.verdict(forItem: item.number),
                  let rowIndex = itemRows[item.number],
                  let matches = itemMatches[item.number]
            else { return false }
            apply(verdict, to: &rows[rowIndex], matches: matches)
        }
        return true
    }

    /// One verdict onto one row.
    ///
    /// An id the shortlist does not hold reads as "none of these" rather than as a hint,
    /// so the model can only ever choose among rows a retriever found and can never name
    /// a food it was not offered.
    ///
    /// Choosing a *different* row of the shortlist is the main thing validation is for —
    /// "oats" retrieving oat biscuits and the model moving it to the oats — so the match
    /// itself is swapped here and not merely noted. That is why this takes the matches
    /// rather than the reduced candidates the prompt was built from: only a `FoodMatch`
    /// carries the values a choice needs.
    private func apply(_ verdict: MatchVerdict, to row: inout ResolvedRow, matches: [FoodMatch]) {
        guard !verdict.isNone,
              let chosen = matches.first(where: { $0.food.id == verdict.candidate })
        else {
            row.choice = nil
            row.confidence = .unsure
            return
        }
        if chosen.food.id != row.choice?.bundledID {
            AppLog.estimation.info("validation moved a row to food \(chosen.food.id)")
            let replacement = remembered(FoodChoice(bundled: chosen.food))
            row.choice = replacement
            // The amount stands. It is what the model estimated was eaten, and being wrong
            // about which row holds the numbers for it does not change how much there was:
            // 40 g of what turned out to be oats rather than oat biscuits is still 40 g.
            // Only the reference moves, because the reference is this person's history with
            // the food that won.
            row.baseAmount = replacement.lastAmount
        }
        row.confidence = switch verdict.certainty {
        case .certain: .settled
        case .probable: .probable
        case .unsure: .unsure
        }
        row.implausible = verdict.implausible || isImplausible(row)
    }

    // MARK: - Amounts

    /// A guard that needs no model: one item coming to more than this is worth a look
    /// whatever anything thinks, which is what catches a powder logged as a drink on a
    /// device with no Apple Intelligence.
    static let implausibleEnergy: Double = 1_200

    private func isImplausible(_ row: ResolvedRow) -> Bool {
        guard let energy = row.nutrition?.energy else { return false }
        return energy > Self.implausibleEnergy
    }

    /// How much, in words, for the prompt.
    private func amountText(_ row: ResolvedRow) -> String {
        guard let choice = row.choice else { return "an unknown amount" }
        if case .recipe = choice.source {
            return Formatters.servings(row.amount)
        }
        return "about \(Formatters.amount(row.amount, measure: choice.measure))"
    }

    // MARK: - Reading a stored item back

    /// The choice behind a remembered item, or `nil` when what it pointed at is gone.
    private func choice(for item: PhraseItem) -> FoodChoice? {
        if let recipe = item.recipe { return recipe.choice }
        return item.food.flatMap(\.choice)
    }
}
