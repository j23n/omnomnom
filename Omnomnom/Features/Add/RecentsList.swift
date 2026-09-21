import Foundation
import SwiftData
import SwiftUI

/// Before any typing: foods and recipes logged before, most recent first, then the
/// recipes and custom foods never logged, so a new recipe is one tap away.
struct RecentsList: View {
    /// Recipes are hidden when picking an ingredient, since recipes do not nest.
    let includesRecipes: Bool
    let onSelect: (FoodChoice) -> Void

    @Query(sort: \Food.lastUsed, order: .reverse) private var foods: [Food]
    @Query(sort: \Recipe.lastUsed, order: .reverse) private var recipes: [Recipe]

    /// Foods and recipes with a last use, merged by that date, at most 20.
    private var recents: [FoodChoice] {
        var items = foods.compactMap { food -> RecentItem? in
            guard let lastUsed = food.lastUsed, let choice = food.choice else { return nil }
            return RecentItem(choice: choice, lastUsed: lastUsed)
        }
        if includesRecipes {
            items += recipes.compactMap { recipe -> RecentItem? in
                guard let lastUsed = recipe.lastUsed else { return nil }
                return RecentItem(choice: recipe.choice, lastUsed: lastUsed)
            }
        }
        return items.sorted { $0.lastUsed > $1.lastUsed }.prefix(20).map(\.choice)
    }

    /// Library items never logged (custom foods, scanned products, recipes), by name.
    private var unused: [FoodChoice] {
        let customFoods = foods.filter { $0.kind != .bundled && $0.lastUsed == nil }.compactMap(\.choice)
        let newRecipes = includesRecipes ? recipes.filter { $0.lastUsed == nil }.map(\.choice) : []
        return (customFoods + newRecipes).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
    }

    private func rows(_ choices: [FoodChoice]) -> some View {
        ForEach(choices) { choice in
            Button {
                onSelect(choice)
            } label: {
                ChoiceRow(choice: choice)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One merged recent: what to reopen and when it was last logged.
private nonisolated struct RecentItem: Hashable, Sendable {
    let choice: FoodChoice
    let lastUsed: Date
}
