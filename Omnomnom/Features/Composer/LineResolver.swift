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
    /// Asked about every term a line names, alongside the bundled tables, and only when
    /// the user has turned product search on. `nil` means nothing may be asked at all.
    let products: ((String) async -> ProductMatch?)?
    /// Names the foods in what was written. `nil` when neither Apple Intelligence nor an
    /// endpoint of the user's own will answer, in which case nothing new can be resolved
    /// and only a line logged before comes back.
    let estimator: (any MealEstimating)?

    init(
        context: ModelContext,
        repository: any FoodSearching,
        validator: (any MatchValidating)? = nil,
        products: ((String) async -> ProductMatch?)? = nil,
        estimator: (any MealEstimating)? = nil
    ) {
        self.context = context
        self.repository = repository
        self.estimator = estimator
        self.validator = validator
        self.products = products
    }

    /// The four rungs as the app wires them, from the two opt-ins that govern them.
    ///
    /// The estimator is whichever model the user chose, and `nil` when none will answer —
    /// then only a line logged before comes back, and the field says as much.
    ///
    /// The validator is separate and present only when the estimation opt-in is on. It is
    /// the second pass, the one that moves "oats" off an oat biscuit, and it is always the
    /// device's own model: a shortlist of candidate rows is a cheap question, and sending
    /// one somewhere would be a second disclosure for a smaller gain.
    ///
    /// The product rung is `nil` when the user has not turned product search on, which is
    /// not the same as a rung that answers nothing: `nil` means nothing may be asked at
    /// all, so an unmatched food goes straight to the user as it did before it existed.
    /// With it on, every term a line names is asked of Open Food Facts as well as of the
    /// tables, and the better score wins; see `ProductRung`.
    static func app(
        context: ModelContext,
        repository: FoodRepository,
        estimationEnabled: Bool,
        productSearchEnabled: Bool
    ) -> LineResolver {
        LineResolver(
            context: context,
            repository: repository,
            validator: estimationEnabled ? FoundationMatchValidator() : nil,
            products: productSearchEnabled ? { await ProductRung.best(for: $0, in: context) } : nil,
            estimator: Estimators.current()
        )
    }

    /// A typed line, resolved.
    func resolve(_ line: String) async -> LineResolution {
        await resolve(.text(line), line: line)
    }

    /// The foods a word could have meant, best first.
    ///
    /// The same search a line goes through, head phrase and all, asked again about one
    /// term — so what a row offers as the alternatives to a guess is the shortlist the
    /// guess was made from rather than a different search that might not contain it.
    /// Nothing is checked by a model here: the user is reading the list themselves, which
    /// is what the second pass exists to spare them, not to compete with.
    func candidates(for term: String) async -> [FoodChoice] {
        await search(term).matches.map { remembered(FoodChoice(bundled: $0.food)) }
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
            let found = await search(item.lookupTerm)
            shortlists[item.id] = found.matches
            rows.append(await databaseRow(for: item, found: found))
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

    /// A shortlist, and whether it answers the whole term or only one word of it.
    private struct Found {
        var matches: [FoodMatch]
        /// True when the whole term found nothing worth showing and one of its words
        /// answered instead. A weaker claim, because the app threw part of what was said
        /// away in order to get an answer at all.
        var wasNarrowed: Bool
    }

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
    private func search(_ term: String) async -> Found {
        guard !term.isEmpty else { return Found(matches: [], wasNarrowed: false) }
        let whole = await shortlist(for: term, scoredAgainst: term)
        if let best = whole.first, best.score >= FoodMatcher.probableAt {
            return Found(matches: whole, wasNarrowed: false)
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
            return Found(matches: whole, wasNarrowed: false)
        }

        var best = whole
        var narrowed = false
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
                narrowed = true
            }
        }
        return Found(matches: best, wasNarrowed: narrowed)
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
                limit: ValidationPrompt.candidatesPerItem
            )
        } catch {
            AppLog.foodDB.error("line lookup failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    /// The best row for one item: the tables and Open Food Facts, whichever answers better.
    ///
    /// A match found by narrowing the term never settles on its own. The retriever answered
    /// a question nobody asked — one word of the term rather than the term — so the row is
    /// marked for a glance however well it scored, and the user sees what the app chose. The
    /// validator can still settle it afterwards, which is the right order: a model that saw
    /// the line and the candidates may know the narrowed answer is the right one, and the
    /// retriever's own confidence cannot.
    ///
    /// Where a product wins, the row is `probable` and never settled: nothing has checked a
    /// stranger's entry. The sign-off screen reads either way, so the cost of a product
    /// winning when it should not have is one tap on a screen already on the user's phone.
    private func databaseRow(for item: ResolvableItem, found: Found) async -> ResolvedRow {
        // Spelled out rather than optional-chained: a chained call on an optional closure
        // whose answer is itself optional gives an optional of an optional.
        let product: ProductMatch?
        if let products {
            product = await products(item.lookupTerm)
        } else {
            product = nil
        }
        let tablesWin = Self.tablesWin(
            bundled: found.matches.first?.score,
            wasNarrowed: found.wasNarrowed,
            product: product?.score
        )
        if let best = found.matches.first, tablesWin {
            let choice = remembered(FoodChoice(bundled: best.food))
            let confidence: MatchConfidence =
                found.wasNarrowed && best.confidence == .settled ? .probable : best.confidence
            return ResolvedRow(
                id: item.id,
                name: item.name,
                choice: choice,
                amount: item.estimated,
                bucket: nil,
                baseAmount: choice.lastAmount,
                origin: .database,
                confidence: confidence
            )
        }
        if let product {
            return ResolvedRow(
                id: item.id,
                name: item.name,
                choice: product.choice,
                amount: item.estimated,
                bucket: nil,
                baseAmount: product.choice.lastAmount,
                origin: .product,
                confidence: .probable
            )
        }
        return ResolvedRow(
            id: item.id, name: item.name, choice: nil, amount: 0,
            origin: .database, confidence: .unsure
        )
    }

    /// Whether the bundled row is the better answer of the two.
    ///
    /// Two clauses and no third. On the plain score the tables win ties, because a
    /// crowdsourced row already paid `SearchRelevance.bonus(isCrowdsourced:)` for being
    /// one — that penalty is the whole of the thumb on the scale, deliberately, so there
    /// is one number to turn rather than a rule to argue about.
    ///
    /// The exception is a table match found by narrowing the term. Narrowing means nothing
    /// answered what was actually said and a word of it was tried instead, so its score is
    /// against a question the user did not ask; a product that answers the whole term is
    /// the better answer even where the number says otherwise. "Spaghetti with bolognese
    /// sauce" is the case: the tables reach a plain spaghetti row by dropping three words,
    /// and a ready meal of that name is what was eaten.
    /// Takes the two scores rather than the two matches, so the rule can be read and
    /// tested on its own terms.
    static func tablesWin(bundled: Double?, wasNarrowed: Bool, product: Double?) -> Bool {
        guard let product else { return true }
        guard let bundled else { return false }
        guard !wasNarrowed else { return false }
        return bundled >= product
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
    ///
    /// **A row the product rung won is not the validator's to judge, and leaving it in was
    /// a bug with teeth.** Inclusion is decided by the shortlist, which is stored for every
    /// item whichever source then won the row — so once Open Food Facts began competing
    /// rather than rescuing, a product that beat the tables on score was handed to the model
    /// as an item whose candidates were the table rows it had just beaten. Both answers
    /// available to the model then threw it away: an id swapped the row onto a table row,
    /// and 0 — the honest answer, since the food the user ate is not on the list — emptied
    /// the row and blocked the log. So the thing `tablesWin` decided was undone a moment
    /// later by a question that could not be answered correctly.
    ///
    /// Skipping those rows is what the rest of the app already says happens: `RowOrigin`
    /// reads "Matched by name, Open Food Facts" with no checked branch at all, and the
    /// sign-off screen is what stands behind a product instead. It also restores the
    /// behaviour that held before the rung competed, when a product only ever appeared
    /// where the tables were empty and the shortlist was empty with them.
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
                  let rowIndex = rows.firstIndex(where: { $0.id == item.id }),
                  rows[rowIndex].origin != .product
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
