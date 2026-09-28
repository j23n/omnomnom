import SwiftUI

/// Name and tag matches from the Library first ("Yours"), then ranked FTS results from
/// the bundled database, then branded products from Open Food Facts when that is turned
/// on. Tapping a row hands a `FoodChoice` back, except a product, which has to be
/// fetched first and goes through `onSelectProduct`. With nothing found, the module
/// buttons offer the other ways in.
struct SearchResultsList: View {
    let local: [FoodChoice]
    let results: [BundledFood]
    let errorMessage: String?
    /// The Scan and Estimate row for the no-results state; `nil` in pick mode.
    let modules: ModuleButtonsRow?
    let products: ProductResults
    let onSelect: (FoodChoice) -> Void
    let onSelectProduct: (ProductRecord) -> Void

    var body: some View {
        List {
            if local.isEmpty, results.isEmpty, errorMessage == nil, !products.hasSomethingToSay {
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
            if products.hasSomethingToSay {
                Section {
                    if let message = products.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if products.records.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Searching Open Food Facts…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(products.records, id: \.code) { record in
                            Button {
                                onSelectProduct(record)
                            } label: {
                                ProductResultRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Products")
                } footer: {
                    Text("From Open Food Facts. Choosing one fetches its values and keeps them here.")
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
        HStack(spacing: 12) {
            PhotoThumbnail(data: nil, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                ValueText(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private let exampleProducts = ProductResults(
    isEnabled: true,
    records: [
        ProductRecord(
            code: "8000500037560", name: "Kinder Bueno", brand: "Ferrero",
            per100g: Nutrition(energy: 571, protein: 8.6, carbohydrates: 49.5, fatTotal: 37.3)
        ),
        ProductRecord(
            code: "5449000000996", name: "Coca-Cola", brand: "Coca-Cola",
            per100g: Nutrition(energy: 42, carbohydrates: 10.6), measure: .volume
        ),
    ]
)

#Preview("Yours and database") {
    SearchResultsList(
        local: PreviewStore.localResults, results: PreviewStore.bundledResults, errorMessage: nil,
        modules: nil, products: ProductResults(), onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("Database only") {
    SearchResultsList(
        local: [], results: PreviewStore.bundledResults, errorMessage: nil,
        modules: nil, products: ProductResults(), onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("No matches") {
    SearchResultsList(
        local: [], results: [], errorMessage: nil,
        modules: nil, products: ProductResults(), onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("No matches, modules on") {
    SearchResultsList(
        local: [], results: [], errorMessage: nil,
        modules: ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false)),
        products: ProductResults(), onSelect: { _ in }, onSelectProduct: { _ in }
    )
    .defaultAppStorage(PreviewDefaults.modulesOn)
}

#Preview("Database missing") {
    SearchResultsList(
        local: PreviewStore.localResults, results: [],
        errorMessage: FoodRepositoryError.databaseMissing.errorDescription,
        modules: nil, products: ProductResults(), onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("With products") {
    SearchResultsList(
        local: [], results: PreviewStore.bundledResults, errorMessage: nil,
        modules: nil, products: exampleProducts, onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("Products still loading") {
    SearchResultsList(
        local: [], results: [], errorMessage: nil, modules: nil,
        products: ProductResults(isEnabled: true, isSearching: true),
        onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("Products unavailable") {
    SearchResultsList(
        local: [], results: PreviewStore.bundledResults, errorMessage: nil, modules: nil,
        products: ProductResults(isEnabled: true, errorMessage: "No connection to Open Food Facts."),
        onSelect: { _ in }, onSelectProduct: { _ in }
    )
}

#Preview("Accessibility 5") {
    SearchResultsList(
        local: PreviewStore.localResults, results: PreviewStore.bundledResults, errorMessage: nil,
        modules: nil, products: exampleProducts, onSelect: { _ in }, onSelectProduct: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
