import Foundation
import os
import SwiftData

/// One candidate from Open Food Facts, with the score it is willing to be judged on.
nonisolated struct ProductMatch: Hashable, Sendable {
    let choice: FoodChoice
    /// Relevance on the same 0-to-1 scale a bundled match carries, the crowdsourced
    /// penalty already taken off, so the two can be compared without a second rule.
    let score: Double
}

/// The fourth rung of the line resolver's ladder: a branded product, found by name.
///
/// A generic composition table has never held a particular jar of peanut butter, so a line
/// naming one used to dead-end on a row with no food and block the log. This answers that
/// case with nothing new sent anywhere: the same opt-in, the same client and the same index
/// the Add screen already searches, and the hit resolved by barcode through the flow a scan
/// uses, so it is cached and attributed identically.
///
/// **It competes rather than rescues.** It used to be consulted only where the tables held
/// nothing, which meant the index was never asked about the foods people mostly eat. Now
/// every term goes to both and the better score wins, which is already what the Add screen
/// does — it reads the bundled tables and Open Food Facts as one ranked list. The thumb on
/// the scale stays: a crowdsourced row carries `SearchRelevance.bonus(isCrowdsourced:)`
/// against it, so a measured row wins a tie and the one number to turn, if brands start
/// winning too often, is that one.
///
/// Opt-in, and never settled. A product row is `probable` at best — marked for a glance,
/// which is the right standing for a stranger's entry that nothing has checked — and every
/// line is read on the sign-off screen before any of it is logged.
enum ProductRung {
    /// The best product for `term`, scored, or nothing.
    ///
    /// One fetch, not several. The resolver compares one product against the tables, and
    /// every further candidate would be a second request abroad for a row nothing looks at.
    static func best(for term: String, in context: ModelContext) async -> ProductMatch? {
        guard ProductResults.isWorthSearching(term) else { return nil }
        let client = OpenFoodFactsClient(
            transport: URLSessionTransport(), userAgent: UserAgent.current()
        )
        let records: [ProductRecord]
        do {
            records = try await client.products(matching: term)
        } catch {
            AppLog.barcode.info("product rung found nothing: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let best = bestMatch(for: term, in: records) else { return nil }
        let flow = BarcodeLookupFlow(context: context, client: client)
        guard case .found(let choice) = await flow.resolve(code: best.code) else { return nil }
        return ProductMatch(choice: choice, score: rank(best, term: term))
    }

    /// The highest-ranked record whose name or brand holds every word of the term.
    ///
    /// The bar is stated here rather than taken on trust, because the index does its own
    /// matching and will answer with a tangential hit — it also matches categories and
    /// labels this app never asked about. The bundled tables apply the same rule by
    /// construction, since their FTS query ands a term's words together.
    ///
    /// Pure, so the bar can be tested without a network.
    static func bestMatch(for term: String, in records: [ProductRecord]) -> ProductRecord? {
        records
            .map { (record: $0, rank: rank($0, term: term)) }
            .filter { $0.rank >= floor }
            .max { $0.rank < $1.rank }?
            .record
    }

    /// Every word of the term present, which is what `SearchRelevance.everyToken` is, less
    /// the penalty every crowdsourced row carries so the two are being compared at the same
    /// scale the merged search list uses.
    static let floor = SearchRelevance.everyToken + SearchRelevance.bonus(isCrowdsourced: true)

    /// What a record scores against a term: every name it carries, less the penalty every
    /// crowdsourced row pays.
    static func rank(_ record: ProductRecord, term: String) -> Double {
        SearchRelevance.rank(
            anyOf: [record.name, record.brand].compactMap { $0 }, query: term,
            bonus: SearchRelevance.bonus(isCrowdsourced: true)
        )
    }
}
