import Foundation
import SwiftData
import SwiftUI

/// Foods logged before, most recent first, so a repeat meal needs no search.
struct RecentsList: View {
    let onSelect: (FoodChoice) -> Void

    @Query(sort: \Food.lastUsed, order: .reverse) private var foods: [Food]

    private var recents: [Food] {
        Array(foods.filter { $0.lastUsed != nil }.prefix(20))
    }

    var body: some View {
        List {
            if recents.isEmpty {
                ContentUnavailableView(
                    "No recent foods",
                    systemImage: "clock",
                    description: Text("Search to find a food. Foods you log appear here.")
                )
                .listRowSeparator(.hidden)
            } else {
                Section("Recent") {
                    ForEach(recents) { food in
                        if let choice = food.choice {
                            Button {
                                onSelect(choice)
                            } label: {
                                RecentRow(food: food)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct RecentRow: View {
    let food: Food

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.name)
            HStack(spacing: 6) {
                if let grams = food.lastGrams {
                    Text("Last \(Formatters.grams(grams))")
                }
                Text(Formatters.amount(food.per100g.energy, unit: .kilocalorie) + " per 100 g")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
