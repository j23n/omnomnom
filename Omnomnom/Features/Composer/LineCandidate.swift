import Foundation
import os
import SwiftData

/// One row a search handed back, as the model reads it and as the app redeems it.
///
/// The id is assigned per request and means nothing outside it. That is a departure from
/// the validation prompt, which names a candidate by its real `foods` row id so a verdict
/// needs no mapping back — and it is forced by there being two sources now. A bundled row
/// and an Open Food Facts product have no shared namespace, and letting table ids through
/// unchanged would mean a product could only be named by something that looks like a table
/// id. One counter over both sources also makes the guard trivial: an id this request
/// never issued is not a food, whatever it resembles.
nonisolated struct LineCandidate: Identifiable, Hashable, Sendable {
    /// What has to happen to turn this candidate into a `FoodChoice`.
    nonisolated enum Pick: Hashable, Sendable {
        /// A bundled row, which already carries its own values.
        case bundled(BundledFood)
        /// A product, by barcode only. The record a name search returns is a starting
        /// point rather than a record, so the chosen one is fetched and cached through the
        /// flow a scan uses — and only the chosen one, which is the whole saving over
        /// asking Open Food Facts twice for every term a line names.
        case product(code: String)
    }

    let id: Int
    let name: String
    /// A category for a bundled row, a brand for a product; absent for either.
    let detail: String?
    /// Energy per 100 g or ml, which is what tells a drink from its powder.
    let energy: Double?
    /// How many of the eight figures the row is short of. A row with gaps is often still
    /// the right answer — a brand that declares only what a label must declare is still
    /// that brand — so this is a count and never a grade.
    let gaps: Int
    /// A dry, raw or concentrated form rather than a portion anyone eats. Said plainly
    /// because it is the one thing a name cannot carry: "Coffee, instant, powder" and the
    /// drink answer the same word and differ by a factor of a hundred.
    let isIngredient: Bool
    let isProduct: Bool
    let pick: Pick

    /// The line the model reads. One per candidate, short, and nothing in it that the
    /// model is then forbidden to use: the energy is evidence for a judgment about form,
    /// which is why it is here, and the instructions say never to report it.
    var promptLine: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty { parts.append(detail) }
        if let energy { parts.append("\(Int(energy.rounded())) kcal/100 g") }
        if isIngredient { parts.append("ingredient or dry form") }
        if isProduct { parts.append("Open Food Facts") }
        if gaps == 1 { parts.append("1 figure missing") } else if gaps > 1 { parts.append("\(gaps) figures missing") }
        let suffix = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "id \(id): \(ValidationPrompt.clean(name))\(suffix)"
    }
}

/// Every candidate the searches returned during one request, by id.
///
/// The pool is the whole of the can't-invent-a-food invariant on this path. The validation
/// prompt gets that property from handing the model a fixed shortlist; here the model
/// chooses what to search for, so the shortlist is not known in advance — but what came
/// back is, and an id outside it reads as "none of these" exactly as 0 does. The model can
/// therefore name a row nobody expected and still cannot name a row nobody found.
nonisolated struct LineCandidatePool: Hashable, Sendable {
    private var byID: [Int: LineCandidate] = [:]
    private var next = 1

    init() {}

    var count: Int { byID.count }

    /// The candidate an id names, or `nil` when this request never issued it.
    func candidate(id: Int) -> LineCandidate? {
        byID[id]
    }

    /// Numbers a search's hits and keeps them. Returns them in the order given, so the
    /// result lines read in the order the matcher ranked them.
    mutating func add(foods: [FoodMatch]) -> [LineCandidate] {
        add(
            foods.map { match in
                LineCandidate(
                    id: 0, name: match.food.name, detail: match.food.category,
                    energy: match.food.per100g.energy,
                    gaps: match.food.per100g.missingNutrients.count,
                    isIngredient: match.food.isIngredient, isProduct: false,
                    pick: .bundled(match.food)
                )
            }
        )
    }

    /// The same for products. A record with no name is dropped rather than numbered: the
    /// model would be choosing between blanks, and the index holds a great many of them.
    mutating func add(products: [ProductRecord]) -> [LineCandidate] {
        add(
            products.compactMap { record in
                guard let name = record.name, !name.isEmpty else { return nil }
                return LineCandidate(
                    id: 0, name: name, detail: record.brand, energy: record.per100g.energy,
                    gaps: record.per100g.missingNutrients.count, isIngredient: false,
                    isProduct: true, pick: .product(code: record.code)
                )
            }
        )
    }

    /// Assigns the ids. The `id: 0` the callers above pass is a placeholder the counter
    /// replaces, so no caller can mint one.
    private mutating func add(_ unnumbered: [LineCandidate]) -> [LineCandidate] {
        var numbered: [LineCandidate] = []
        for candidate in unnumbered {
            let id = next
            next += 1
            let placed = LineCandidate(
                id: id, name: candidate.name, detail: candidate.detail, energy: candidate.energy,
                gaps: candidate.gaps, isIngredient: candidate.isIngredient,
                isProduct: candidate.isProduct, pick: candidate.pick
            )
            byID[id] = placed
            numbered.append(placed)
        }
        return numbered
    }
}

/// The two searches a model may ask for, run on this device.
///
/// A protocol so the loop can be driven without a database or a network, and `@MainActor`
/// because both searches end up at the shared `ModelContext` — the product one writes a
/// cache row. That is also why the loop that calls this is main-actor rather than an
/// actor of its own.
@MainActor
protocol LineSearching: Sendable {
    /// Whether the product search may be offered at all. With the opt-in off nothing may
    /// be asked of Open Food Facts, which is not the same as a search that answers
    /// nothing: an undeclared tool cannot be called, so the model never spends a round
    /// trip discovering that it is empty.
    var searchesProducts: Bool { get }
    func foods(matching term: String) async -> [FoodMatch]
    func products(matching term: String) async -> [ProductRecord]
}

/// The searches as the app wires them: the bundled tables through the same matcher the
/// rest of the app ranks with, and Open Food Facts through the client the Add screen
/// already uses.
///
/// Deliberately thin. Everything here has a counterpart in `LineResolver`'s own rungs, and
/// the point of this path is that the strategy above it — which term to try, whether to try
/// another — moves to the model instead of being written out as a fallback rule.
@MainActor
struct AppLineSearch: LineSearching {
    let repository: any FoodSearching
    let client: OpenFoodFactsClient
    let searchesProducts: Bool

    /// The searches as the app wires them, from the one opt-in that governs the second.
    ///
    /// One factory because two entry points need it — the composer and the Siri intent —
    /// and a second construction of this would be a second chance to disagree about
    /// whether Open Food Facts may be asked.
    static func app(repository: any FoodSearching, productSearchEnabled: Bool) -> AppLineSearch {
        AppLineSearch(
            repository: repository,
            client: OpenFoodFactsClient(transport: URLSessionTransport(), userAgent: UserAgent.current()),
            searchesProducts: productSearchEnabled
        )
    }

    /// How many rows one search answers with. Larger than the validation prompt's six,
    /// because a model that can search again does better with a wider look than with a
    /// second round trip, and the whole list is a few hundred bytes.
    static let limit = 10

    func foods(matching term: String) async -> [FoodMatch] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            return FoodMatcher.shortlist(
                try await repository.search(trimmed), term: trimmed, limit: Self.limit
            )
        } catch {
            AppLog.foodDB.error("tool search failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    func products(matching term: String) async -> [ProductRecord] {
        guard searchesProducts, ProductResults.isWorthSearching(term) else { return [] }
        do {
            return Array(try await client.products(matching: term).prefix(Self.limit))
        } catch {
            AppLog.barcode.info("tool product search found nothing: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
