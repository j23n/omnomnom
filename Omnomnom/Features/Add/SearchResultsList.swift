import SwiftUI

/// Ranked FTS results. Tapping a row hands a `FoodChoice` to the Quantity sheet.
struct SearchResultsList: View {
    let results: [BundledFood]
    let errorMessage: String?
    let onSelect: (FoodChoice) -> Void

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView(
                    "Search unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .listRowSeparator(.hidden)
            } else if results.isEmpty {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
            } else {
                ForEach(results) { food in
                    Button {
                        onSelect(FoodChoice(bundled: food))
                    } label: {
                        ResultRow(food: food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct ResultRow: View {
    let food: BundledFood

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.name)
            HStack(spacing: 6) {
                if let category = food.category {
                    Text(category)
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
