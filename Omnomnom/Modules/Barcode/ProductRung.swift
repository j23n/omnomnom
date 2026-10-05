import Foundation
import os
import SwiftData

/// The fourth rung of the line resolver's ladder: a branded product, by name, for a food
/// the bundled tables hold nothing for.
///
/// A generic composition table has never held a particular jar of peanut butter, so a line
/// naming one used to dead-end on a row with no food and block the log. This answers that
/// case with nothing new sent anywhere: the same opt-in, the same client and the same index
/// the Add screen already searches, and the hit resolved by barcode through the flow a scan
/// uses, so it is cached and attributed identically.
///
/// Strictly a fallback and strictly opt-in. The bundled tables are tried first because they
/// are offline, licence-clean and analytically measured; a crowdsourced record is consulted
/// only when there is nothing better, and the row it produces is never settled — `probable`
/// at best, marked for a glance, which is the right standing for a stranger's entry that
/// nothing has checked.
enum ProductRung {
    /// The best product for `term`, as the shortlist the resolver reads, or nothing.
    ///
    /// One fetch, not several. The resolver reads the first element only, and every further
    /// candidate would be a second request abroad for a row nothing looks at.
    static func choices(for term: String, in context: ModelContext) async -> [FoodChoice] {
        guard ProductResults.isWorthSearching(term) else { return [] }
        let client = OpenFoodFactsClient(
            transport: URLSessionTransport(), userAgent: UserAgent.current()
        )
        let records: [ProductRecord]
        do {
            records = try await client.products(matching: term)
        } catch {
            AppLog.barcode.info("product rung found nothing: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard let best = bestMatch(for: term, in: records) else { return [] }
        let flow = BarcodeLookupFlow(context: context, client: client)
        guard case .found(let choice) = await flow.resolve(code: best.code) else { return [] }
        return [choice]
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

    private static func rank(_ record: ProductRecord, term: String) -> Double {
        SearchRelevance.rank(
            anyOf: [record.name, record.brand].compactMap { $0 }, query: term,
            bonus: SearchRelevance.bonus(isCrowdsourced: true)
        )
    }
}
