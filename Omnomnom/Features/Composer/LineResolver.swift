import Foundation
import SwiftData
import os

/// Turning a typed line into rows that can be logged.
///
/// Four rungs, tried in order, and the order is the whole design:
///
/// 1. **Phrase recall.** The whole line has been logged before, so every food and every
///    amount comes back from the last time. Nothing is parsed, nothing is searched, and
///    no model is asked — which is what keeps a repeat under five seconds.
/// 2. **Item recall.** A familiar food inside a line that is otherwise new.
/// 3. **The bundled tables**, through FTS5 and `FoodMatcher`.
/// 4. **Open Food Facts**, when the product opt-in is on and the tables held nothing.
///
/// Rungs 3 and 4 are then checked by the model in one request, where there is a model.
/// Rungs 1 and 2 are not: the user already asserted those, so there is nothing to check.
///
/// Main-actor because recall and `FoodChoice` construction read a `ModelContext`; the
/// search and the validation are awaited into their own actors.
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

    init(
        context: ModelContext,
        repository: any FoodSearching,
        validator: (any MatchValidating)? = nil,
        products: ((String) async -> [FoodChoice])? = nil
    ) {
        self.context = context
        self.repository = repository
        self.validator = validator
        self.products = products
    }

    /// The line, resolved. Never throws: a failure anywhere leaves rows unmatched for
    /// the user to settle, which is a worse outcome than a good match and a far better
    /// one than an error where a meal should be.
    func resolve(_ line: String) async -> LineResolution {
        if let recalled = recallWholeLine(line) {
            return recalled
        }
        let parsed = LineParser.parse(line)
        guard !parsed.isEmpty else {
            return LineResolution(line: line, rows: [], wasChecked: false)
        }

        var rows: [ResolvedRow] = []
        var shortlists: [UUID: [FoodMatch]] = [:]
        for item in parsed {
            if let row = recallItem(item) {
                rows.append(row)
                continue
            }
            let shortlist = await search(item.lookupTerm)
            shortlists[item.id] = shortlist
            rows.append(await databaseRow(for: item, shortlist: shortlist))
        }

        // One request for the whole line, and only for the rows a retriever chose.
        let checked = await check(line: line, parsed: parsed, shortlists: shortlists, rows: &rows)
        return LineResolution(line: line, rows: rows, wasChecked: checked)
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
                origin: .phrase,
                confidence: .settled
            )
        }
        guard rows.count == items.count, !rows.isEmpty else { return nil }
        return LineResolution(line: line ?? phrase.text, rows: rows, wasChecked: false)
    }

    /// One fragment from memory, or `nil` when that fragment has no record.
    private func recallItem(_ item: ParsedItem) -> ResolvedRow? {
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
            amount: amount(for: item, choice: choice, reference: stored.amount),
            bucket: item.size ?? .usual,
            // The reference a step multiplies is what was stored, so "less" after the
            // line already said "big" is less than usual rather than less than big.
            baseAmount: stored.amount,
            origin: .item,
            confidence: .settled
        )
    }

    // MARK: - Rung three and four: what the database says

    private func search(_ term: String) async -> [FoodMatch] {
        guard !term.isEmpty else { return [] }
        do {
            return FoodMatcher.shortlist(
                try await repository.search(term), term: term,
                limit: ValidationPrompt.candidatesPerItem
            )
        } catch {
            AppLog.foodDB.error("line lookup failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    /// A row from the best match, falling back to a product when the tables held nothing.
    private func databaseRow(for item: ParsedItem, shortlist: [FoodMatch]) async -> ResolvedRow {
        if let best = shortlist.first {
            let choice = FoodChoice(bundled: best.food)
            return ResolvedRow(
                id: item.id,
                name: item.name,
                choice: choice,
                amount: amount(for: item, choice: choice, reference: nil),
                bucket: bucket(for: item, choice: choice, reference: nil),
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
                amount: amount(for: item, choice: product, reference: nil),
                bucket: bucket(for: item, choice: product, reference: nil),
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

    // MARK: - Checking

    /// Asks the model to choose among the rows a retriever found, and applies what it
    /// says. Returns whether the line was checked at all.
    ///
    /// All-or-nothing: a validator that throws, is cancelled or answers short leaves the
    /// whole line unchecked rather than some rows checked and others not.
    private func check(
        line: String, parsed: [ParsedItem], shortlists: [UUID: [FoodMatch]],
        rows: inout [ResolvedRow]
    ) async -> Bool {
        guard let validator, !shortlists.isEmpty else { return false }
        var items: [ValidationItem] = []
        var itemRows: [Int: Int] = [:]
        var itemMatches: [Int: [FoodMatch]] = [:]
        for item in parsed {
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
            let replacement = FoodChoice(bundled: chosen.food)
            row.choice = replacement
            // The amount was scaled against the row that lost, so it is taken again
            // against the one that won.
            if row.bucket == nil {
                row.amount = defaultAmount(for: replacement)
            } else if let bucket = row.bucket {
                row.amount = bucket.amount(of: replacement.lastAmount ?? defaultAmount(for: replacement))
            }
        }
        row.confidence = switch verdict.certainty {
        case .certain: .settled
        case .probable: .probable
        case .unsure: .unsure
        }
        row.implausible = verdict.implausible || isImplausible(row)
    }

    // MARK: - Amounts

    /// The amount a row starts at.
    ///
    /// Precedence, and the reasoning for it: an amount the line actually wrote wins over
    /// everything, because the user said it. Then what they last had of this food in this
    /// phrase, which is better evidence than any generic figure. Then a count against a
    /// portion row. Then the food's own last amount, then a plain reference.
    private func amount(for item: ParsedItem, choice: FoodChoice, reference: Double?) -> Double {
        if let written = item.amount { return written }
        let base = reference ?? choice.lastAmount ?? defaultAmount(for: choice)
        if let count = item.count, reference == nil, choice.lastAmount == nil {
            return base * count
        }
        if let size = item.size { return size.amount(of: base) }
        return base
    }

    /// The step a row shows, or `nil` when there is no history to multiply.
    ///
    /// "Usual" has to mean this person's usual. On a food eaten for the first time there
    /// is nothing to multiply, and offering the same control would make one word mean a
    /// measured fact on one row and a population guess on the next.
    private func bucket(for item: ParsedItem, choice: FoodChoice, reference: Double?) -> AmountBucket? {
        guard reference != nil || choice.lastAmount != nil else { return nil }
        return item.size ?? .usual
    }

    /// A reference for a food never logged: one serving of a recipe, else 100 of its own
    /// unit, which is what the bundled tables are published in.
    private func defaultAmount(for choice: FoodChoice) -> Double {
        if case .recipe = choice.source { return 1 }
        return 100
    }

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
