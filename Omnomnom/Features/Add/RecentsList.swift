import Foundation
import SwiftData
import SwiftUI

/// Before any typing: the module buttons when a module is on, then foods and recipes
/// logged before, most recent first, then the recipes and custom foods never logged, so
/// a new recipe is one tap away.
///
/// Rows are the same `SearchResultRow` the results use, without the provenance pill:
/// the headings already say that everything here is yours or something you have eaten,
/// so a pill on every row would label a list that cannot vary. Relevance is not
/// consulted either — these are ordered by when they were last eaten, which is a better
/// guess than any score.
struct RecentsList: View {
    /// Recipes are hidden when picking an ingredient, since recipes do not nest.
    let includesRecipes: Bool
    /// The Scan and Estimate row; `nil` in pick mode.
    let modules: ModuleButtonsRow?
    let onSelect: (SearchResult) -> Void

    @Query(sort: \Food.lastUsed, order: .reverse) private var foods: [Food]
    @Query(sort: \Recipe.lastUsed, order: .reverse) private var recipes: [Recipe]

    /// Foods and recipes with a last use, merged by that date, at most 20.
    private var recents: [SearchResult] {
        var items = foods.compactMap { food -> RecentItem? in
            guard let lastUsed = food.lastUsed,
                  let result = SearchResult.make(food: food, query: "") else { return nil }
            return RecentItem(result: result, lastUsed: lastUsed)
        }
        if includesRecipes {
            items += recipes.compactMap { recipe -> RecentItem? in
                guard let lastUsed = recipe.lastUsed else { return nil }
                return RecentItem(result: SearchResult.make(recipe: recipe, query: ""), lastUsed: lastUsed)
            }
        }
        return items.sorted { $0.lastUsed > $1.lastUsed }.prefix(20).map(\.result)
    }

    /// Library items never logged (custom foods, scanned products, recipes), by name.
    private var unused: [SearchResult] {
        let customFoods = foods
            .filter { $0.kind != .bundled && $0.lastUsed == nil }
            .compactMap { SearchResult.make(food: $0, query: "") }
        let newRecipes = includesRecipes
            ? recipes.filter { $0.lastUsed == nil }.map { SearchResult.make(recipe: $0, query: "") }
            : []
        return (customFoods + newRecipes)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if recents.isEmpty, unused.isEmpty {
                ContentUnavailableView(
                    "No recent foods",
                    systemImage: "clock",
                    description: Text("Search to find a food. Foods you log appear here.")
                )
                .listRowSeparator(.hidden)
            }
            if let modules {
                modules
            }
            if !recents.isEmpty {
                Section("Recent") {
                    rows(recents)
                }
            }
            if !unused.isEmpty {
                Section("Yours") {
                    rows(unused)
                }
            }
        }
        .listStyle(.plain)
        .readableColumn()
    }

    private func rows(_ results: [SearchResult]) -> some View {
        ForEach(results) { result in
            Button {
                onSelect(result)
            } label: {
                SearchResultRow(result: result, showsSource: false)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One merged recent: what to reopen and when it was last logged.
private nonisolated struct RecentItem: Hashable, Sendable {
    let result: SearchResult
    let lastUsed: Date
}

#if DEBUG
#Preview("Recents and yours") {
    RecentsList(includesRecipes: true, modules: nil) { _ in }
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Nothing logged yet") {
    RecentsList(includesRecipes: true, modules: nil) { _ in }
        .previewEnvironment(seed: .empty)
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 768)) {
    RecentsList(includesRecipes: true, modules: nil) { _ in }
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Accessibility 5") {
    RecentsList(includesRecipes: true, modules: nil) { _ in }
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
