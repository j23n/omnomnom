import SwiftUI

/// Name matches from the Library first ("Yours"), then ranked FTS results from the
/// bundled database. Tapping a row hands a `FoodChoice` to whoever opened the sheet.
struct SearchResultsList: View {
    let local: [FoodChoice]
    let results: [BundledFood]
    let errorMessage: String?
    let onSelect: (FoodChoice) -> Void

    var body: some View {
        List {
            if local.isEmpty, results.isEmpty, errorMessage == nil {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
            }
            if !local.isEmpty {
                Section("Yours") {
                    ForEach(local) { choice in
                        Button {
                            onSelect(choice)
                        } label: {
                            ChoiceRow(choice: choice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let errorMessage {
                Section("Database") {
                    ContentUnavailableView(
                        "Search unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    .listRowSeparator(.hidden)
                }
            } else if !results.isEmpty {
                Section("Database") {
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
