import Foundation
import os
import SwiftData

extension LineResolver {
    /// A line resolved by a model that did its own searching.
    ///
    /// This is how a line is read. There used to be a ladder beside it — name the foods,
    /// retrieve a shortlist per food, ask a second model to choose from it, and recover
    /// with a word-dropping fallback when a term found nothing — and all of it existed
    /// because the model naming the foods could not see the database and had to guess the
    /// wording a composition table uses. A model that looks needs none of it, so the
    /// ladder is gone: no `lookupTerm`, no narrowing, no arbitration between two
    /// retrievers. The rows of both sources arrive as candidates in one list and the model
    /// picks among them.
    ///
    /// What the ladder had that was worth keeping is in front of this: a whole line logged
    /// before comes back from memory before anything is asked, which `resolve` handles
    /// before it gets here.
    ///
    /// Never throws, for the same reason the other path does not: a failure anywhere leaves
    /// rows for the user to settle, and an empty resolution is a thing the composer already
    /// knows how to say.
    func resolve(_ input: EstimationInput, line: String, driving driver: any LineDriving) async -> LineResolution {
        let driven: DrivenLine
        do {
            driven = try await driver.resolve(input)
        } catch {
            AppLog.estimation.info("line unresolved: \(error.localizedDescription, privacy: .public)")
            return LineResolution(
                line: line, rows: [], wasChecked: false, failure: LineResolver.sentence(for: error)
            )
        }
        var rows: [ResolvedRow] = []
        for item in driven.answer.items {
            guard let row = await row(for: item, in: driven.pool) else { continue }
            rows.append(row)
        }
        guard !rows.isEmpty else {
            return LineResolution(line: line, rows: [], wasChecked: false)
        }
        // Checked, and more thoroughly than the other path means by it: every row here is
        // one the model read and chose, rather than one a retriever chose and the model
        // was asked to confirm. The sheet's sentence is true either way.
        return LineResolution(
            line: line, rows: rows, wasChecked: true, meal: driven.answer.meal.slot
        )
    }

    /// One answered item as a row, or `nil` when there is nothing worth showing.
    ///
    /// An item with no usable weight is dropped rather than clamped, which is the rule
    /// `EstimateConversion` already applies to the other path: a dropped row is honest and
    /// an invented weight is not. An item whose candidate is 0, or an id this request never
    /// issued, keeps its row — that is the model saying neither search holds the food, and
    /// the row goes to the user to settle exactly as an unmatched row always has.
    private func row(for item: ResolvedLineItem, in pool: LineCandidatePool) async -> ResolvedRow? {
        guard item.grams.isFinite, item.grams > 0 else { return nil }
        let grams = min(max(item.grams, Formatters.minimumAmount), Formatters.maximumAmount)
        let name = EstimateConversion.cleanName(item.name)
        guard item.candidate != 0, let candidate = pool.candidate(id: item.candidate) else {
            if item.candidate != 0 {
                AppLog.estimation.info("answered with candidate \(item.candidate), which was never offered")
            }
            return ResolvedRow(
                name: name, choice: nil, amount: 0, origin: .database, confidence: .unsure
            )
        }
        switch candidate.pick {
        case .bundled(let food):
            let choice = remembered(FoodChoice(bundled: food))
            var row = ResolvedRow(
                name: name, choice: choice, amount: grams, bucket: nil,
                baseAmount: choice.lastAmount, origin: .database,
                confidence: Self.confidence(item.certainty, isIngredient: food.isIngredient)
            )
            row.implausible = item.implausible || row.isImplausibleByEnergy
            return row
        case .product(let code):
            return await productRow(name: name, code: code, grams: grams, item: item)
        }
    }

    /// A chosen product, fetched and cached through the flow a scan uses.
    ///
    /// This is a round trip the old path spent. It asked Open Food Facts twice for every
    /// term a line named — once to search, once to fetch the best hit by barcode —
    /// whether or not anything then used the answer. Here the search is a tool result and
    /// the fetch happens once, for the row that won.
    private func productRow(
        name: String, code: String, grams: Double, item: ResolvedLineItem
    ) async -> ResolvedRow {
        let client = OpenFoodFactsClient(transport: URLSessionTransport(), userAgent: UserAgent.current())
        let flow = BarcodeLookupFlow(context: context, client: client)
        guard case .found(let choice) = await flow.resolve(code: code) else {
            // Found by name and then not usable: no energy figure, or no connection by the
            // time the fetch went out. The row keeps its origin so the sheet can say where
            // it came from, and blocks, because there are no values behind it.
            AppLog.barcode.info("a chosen product did not resolve")
            return ResolvedRow(
                name: name, choice: nil, amount: 0, origin: .product, confidence: .unsure
            )
        }
        var row = ResolvedRow(
            name: name, choice: choice, amount: grams, bucket: nil,
            baseAmount: choice.lastAmount, origin: .product,
            // Never settled, which is the rule a product has always been held to, and the
            // reason survives this path: the model can confirm *which* product this is —
            // it read the name, the brand and the energy — but not whether a stranger
            // typed the figures in correctly, and it is the figures that reach Health.
            confidence: Self.noBetterThanProbable(Self.confidence(item.certainty, isIngredient: false))
        )
        row.implausible = item.implausible || row.isImplausibleByEnergy
        return row
    }

    /// A confidence held to `probable`, for the two rows that may never settle unasked.
    private static func noBetterThanProbable(_ confidence: MatchConfidence) -> MatchConfidence {
        confidence == .settled ? .probable : confidence
    }

    /// The model's certainty as a row's confidence.
    ///
    /// One override, and it is the one defence that works on every device: an ingredient or
    /// dry form never settles unasked. The model is told which candidates are marked as one
    /// and told they are rarely what was eaten, so choosing one anyway is a deliberate act
    /// and worth more than a score — but "Coffee, instant, powder" settled at a portion
    /// weight is a hundredfold energy error landing silently in a trend, and one glance is
    /// a cheap insurance against it. Capped rather than refused, which is where this differs
    /// from `FoodMatch.confidence`: the scorer has no idea what the row is, and this model
    /// does.
    static func confidence(_ certainty: VerdictCertainty, isIngredient: Bool) -> MatchConfidence {
        let stated = certainty.confidence
        return isIngredient ? noBetterThanProbable(stated) : stated
    }
}
