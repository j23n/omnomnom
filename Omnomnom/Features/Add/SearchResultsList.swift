import SwiftUI

/// Name matches from the Library first ("Yours"), then ranked FTS results from the
/// bundled database. Tapping a row hands a `FoodChoice` to whoever opened the sheet.
/// With nothing found, the module buttons offer the other ways in.
struct SearchResultsList: View {
    let local: [FoodChoice]
    let results: [BundledFood]
    let errorMessage: String?
    /// The Scan and Estimate row for the no-results state; `nil` in pick mode.
    let modules: ModuleButtonsRow?
    let onSelect: (FoodChoice) -> Void

    var body: some View {
        List {
            if local.isEmpty, results.isEmpty, errorMessage == nil {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
                if let modules {
                    modules
                }
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

    /// "Fruits and Fruit Juices · 52 kcal per 100 g", wrapping as one line of text. The
    /// bundled database is per 100 g throughout, so the unit is settled here.
    private var caption: String {
        var parts: [String] = []
        if let category = food.category {
            parts.append(category)
        }
        parts.append("\(Formatters.amount(food.per100g.energy, unit: .kilocalorie)) \(FoodMeasure.mass.referenceText)")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.name)
            ValueText(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Yours and database") {
    SearchResultsList(local: PreviewStore.localResults, results: PreviewStore.bundledResults, errorMessage: nil, modules: nil) { _ in }
}

#Preview("Database only") {
    SearchResultsList(local: [], results: PreviewStore.bundledResults, errorMessage: nil, modules: nil) { _ in }
}

#Preview("No matches") {
    SearchResultsList(local: [], results: [], errorMessage: nil, modules: nil) { _ in }
}

#Preview("No matches, modules on") {
    SearchResultsList(
        local: [], results: [], errorMessage: nil,
        modules: ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false))
    ) { _ in }
    .defaultAppStorage(PreviewDefaults.modulesOn)
}

#Preview("Database missing") {
    SearchResultsList(
        local: PreviewStore.localResults, results: [],
        errorMessage: FoodRepositoryError.databaseMissing.errorDescription, modules: nil
    ) { _ in }
}

#Preview("Accessibility 5") {
    SearchResultsList(local: PreviewStore.localResults, results: PreviewStore.bundledResults, errorMessage: nil, modules: nil) { _ in }
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
