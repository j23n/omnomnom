import Foundation
import os

/// One item of the estimate after the lookup: the name the user sees, the weight eaten,
/// and the food every nutrient value comes from. `choice` is `nil` when the database had
/// nothing for it; such a row is never logged, the user picks a food or removes it.
nonisolated struct ResolvedEstimateItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var grams: Double
    var choice: FoodChoice?

    init(id: UUID = UUID(), name: String, grams: Double, choice: FoodChoice?) {
        self.id = id
        self.name = name
        self.grams = grams
        self.choice = choice
    }

    /// What the matched food holds in this portion; `nil` while nothing is matched.
    var nutrition: Nutrition? {
        choice?.snapshot(for: grams)
    }
}

/// The one thing the resolver needs from the bundled database, so a test can stand in
/// for it. `FoodRepository` is what the app injects into the environment.
nonisolated protocol FoodSearching: Sendable {
    func search(_ text: String) async throws -> [BundledFood]
}

extension FoodRepository: FoodSearching {}

/// Gives each estimated item a real food from the bundled database, which is where every
/// nutrient value then comes from. The generic lookup term is searched first and the
/// displayed name second, and the best hit the search returns is taken.
///
/// Searches run one after another rather than at once: there are at most twelve items,
/// and the same estimate resolving the same way every time is worth more than the speed.
nonisolated struct EstimateResolver: Sendable {
    let repository: any FoodSearching

    init(repository: any FoodSearching) {
        self.repository = repository
    }

    /// The items in their original order, each with the food it matched or `nil`. A
    /// cancelled task stops searching and returns what it has; the caller drops it.
    func resolve(_ items: [EstimatedDraftItem]) async -> [ResolvedEstimateItem] {
        var resolved: [ResolvedEstimateItem] = []
        resolved.reserveCapacity(items.count)
        for item in items {
            guard !Task.isCancelled else { break }
            let choice = await match(item)
            resolved.append(ResolvedEstimateItem(id: item.id, name: item.name, grams: item.grams, choice: choice))
        }
        return resolved
    }

    /// The lookup term's first hit, else the name's; `nil` when neither finds anything.
    private func match(_ item: EstimatedDraftItem) async -> FoodChoice? {
        let term = item.lookupTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hit = await firstHit(for: term) { return hit }
        guard name != term else { return nil }
        return await firstHit(for: name)
    }

    /// One search, best hit first. A blank query is not searched, and a failed search
    /// leaves the row unmatched instead of failing the whole estimate.
    private func firstHit(for text: String) async -> FoodChoice? {
        guard !text.isEmpty else { return nil }
        do {
            guard let found = try await repository.search(text).first else { return nil }
            return FoodChoice(bundled: found)
        } catch {
            AppLog.foodDB.error("estimate lookup failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
