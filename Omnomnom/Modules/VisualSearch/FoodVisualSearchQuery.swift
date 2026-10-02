import AppIntents
import Foundation
import os
import VisualIntelligence

/// Choosing which bundled foods answer a set of visual-intelligence labels.
///
/// Pure, so the choice is testable without a camera.
nonisolated enum VisualFoodMatch {
    /// How many foods go back. Visual intelligence shows a few at a time and wants an
    /// answer quickly, and a camera pointed at a plate is a vaguer question than a
    /// typed word: ten good guesses are more use than fifty.
    static let limit = 10
    /// How many labels are searched. They arrive most confident first.
    static let maximumLabels = 6

    /// The best foods across every label, each scored against the label that found it.
    ///
    /// A food found by two labels keeps its better score rather than counting twice,
    /// and foods that score the same are ordered by id so the same scene always
    /// answers the same way.
    static func best(
        from hits: [(label: String, foods: [BundledFood])], limit: Int = limit
    ) -> [BundledFood] {
        var best: [Int: (food: BundledFood, rank: Double)] = [:]
        for (label, foods) in hits {
            for food in foods {
                let rank = SearchRelevance.rank(anyOf: [food.name], query: label, bonus: 0)
                if let existing = best[food.id], existing.rank >= rank { continue }
                best[food.id] = (food, rank)
            }
        }
        return best.values
            .sorted { $0.rank == $1.rank ? $0.food.id < $1.food.id : $0.rank > $1.rank }
            .prefix(limit)
            .map(\.food)
    }
}

/// What visual intelligence asks the app when someone points the camera at food.
///
/// The system hands over the labels it recognised — general terms in en_US, "fruit"
/// rather than "Braeburn" — and the app answers with its own foods. Only the labels are
/// read, not the `pixelBuffer` the descriptor also offers: this surface wants a list of
/// foods in a moment, and running an estimate on the frame would answer a different
/// question, slowly, and only on the devices that have the model. The frame is there
/// when that becomes worth doing.
///
/// Nothing leaves the device here. The bundled database is local and so is the search.
nonisolated struct FoodVisualSearchQuery: IntentValueQuery {
    @Dependency private var repository: FoodRepository

    func values(for input: SemanticContentDescriptor) async throws -> [FoodEntity] {
        let labels = Array(input.labels.prefix(VisualFoodMatch.maximumLabels))
        guard !labels.isEmpty else { return [] }
        var hits: [(label: String, foods: [BundledFood])] = []
        for label in labels {
            guard !Task.isCancelled else { break }
            // A label that finds nothing, or a database that cannot be read, is no
            // reason to answer with nothing at all.
            let found = (try? await repository.search(label)) ?? []
            hits.append((label: label, foods: found))
        }
        let foods = VisualFoodMatch.best(from: hits)
        AppLog.foodDB.info("visual search: \(labels.count) labels, \(foods.count) foods")
        return foods.map(FoodEntity.init)
    }
}
