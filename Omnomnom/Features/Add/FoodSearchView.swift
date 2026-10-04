import Foundation
import os
import SwiftData
import SwiftUI

/// Which sheet the food search screen has up. One slot, so two can never fight over it.
private nonisolated enum FoodSearchSheet: Identifiable, Sendable {
    /// A food picked in log mode, on its way to being logged.
    case quantity(FoodChoice)
    /// A product Open Food Facts knows by name but not by its values, to type from the label.
    case product(ProductPrefill)

    var id: String {
        switch self {
        case .quantity(let choice): "quantity-\(choice.id)"
        case .product(let prefill): "product-\(prefill.barcode)"
        }
    }
}

/// What the food search screen does with a tapped row.
enum AddFoodMode {
    /// Open the Quantity sheet for `day`; a completed log closes the screen. An
    /// estimate logs several entries at once and reports through `onMessage` instead.
    case log(day: Date, onLogged: (LogResult) -> Void, onMessage: (String) -> Void)
    /// Hand the choice back at once. With `multiple`, the screen stays open and keeps
    /// taking foods until Done, which is how a recipe's ingredients are gathered.
    /// Recipes are hidden either way: recipes do not nest.
    case pick(multiple: Bool, onPick: (FoodChoice) -> Void)
}

/// A screen for finding a food: the Library, the bundled database and, when it is
/// turned on, Open Food Facts, under one search field. The user's own foods come first
/// and the other two are read as one ranked list below them. Recents show before any
/// typing. In log mode, and with the module on, a Scan button leads to the barcode
/// flow and an Estimate button to on-device estimation.
///
/// Presented full screen rather than as a sheet. Finding a food is the longest task in
/// the app, and it deserves the whole display and a search field that is there from the
/// first frame instead of arriving after the list.
struct FoodSearchView: View {
    let mode: AddFoodMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var local: [SearchResult] = []
    @State private var database: [SearchResult] = []
    @State private var databaseError: String?
    @State private var products = ProductResults()
    @State private var sheet: FoodSearchSheet?
    /// A food to open once the sheet in front of it has gone. Presenting from inside a
    /// sheet's own callback loses the second presentation, so it waits for `onDismiss`.
    @State private var pendingChoice: FoodChoice?
    @State private var scanRequested = false
    @State private var estimateRequested = false
    /// How many foods have gone back to the caller in a multiple pick, and the last of
    /// them, so the bottom bar can say what happened without anything else moving.
    @State private var pickedCount = 0
    @State private var lastPicked: String?
    @FocusState private var fieldFocused: Bool
    @AppStorage(BarcodeModule.productSearchKey) private var productSearchEnabled = false

    /// How long a keystroke is given to be followed by another before the Library and
    /// the bundled database are searched. Both are on this device, so it is short.
    private static let localDebounce = Duration.milliseconds(150)

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !query.isEmpty
    }

    private var includesRecipes: Bool {
        if case .log = mode { return true }
        return false
    }

    private var picksSeveral: Bool {
        if case .pick(let multiple, _) = mode { return multiple }
        return false
    }

    private var title: String {
        switch mode {
        case .log: "Add food"
        case .pick(let multiple, _): multiple ? "Add ingredients" : "Choose a food"
        }
    }

    /// The day being logged into; `nil` in pick mode, which has no estimation.
    private var logDay: Date? {
        if case .log(let day, _, _) = mode { return day }
        return nil
    }

    /// The Scan and Estimate row for the lists; `nil` in pick mode, where neither applies.
    private var modules: ModuleButtonsRow? {
        guard includesRecipes else { return nil }
        return ModuleButtonsRow(scanRequested: $scanRequested, estimateRequested: $estimateRequested)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FoodSearchField(text: $searchText, prompt: "Search foods", isFocused: $fieldFocused)
                if isSearching {
                    SearchResultsList(
                        sections: sections, databaseError: databaseError,
                        products: products, modules: modules,
                        onSelect: { select($0) }
                    )
                } else {
                    RecentsList(includesRecipes: includesRecipes, modules: modules) { select($0) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { fieldFocused = true }
            .task(id: searchText) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(pickedCount > 0 ? "Done" : "Cancel") { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                if pickedCount > 0 {
                    pickedBar
                }
            }
            .sheet(item: $sheet, onDismiss: { advance() }) { sheet in
                switch sheet {
                case .quantity(let choice):
                    if case .log(let day, let onLogged, _) = mode {
                        QuantitySheet(choice: choice, day: day) { result in
                            self.sheet = nil
                            onLogged(result)
                            dismiss()
                        }
                        .presentationDetents([.medium, .large])
                    }
                case .product(let prefill):
                    CustomFoodEditorView(food: nil, product: prefill) { food in
                        pendingChoice = food.choice
                    }
                }
            }
            .modifier(BarcodeEntryPoint(isActive: includesRecipes, isRequested: $scanRequested) { present($0) })
            .modifier(EstimationEntryPoint(day: logDay, isRequested: $estimateRequested) { estimated($0) })
        }
    }

    /// What a multiple pick has gathered so far, with the way out of the screen.
    private var pickedBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pickedCount == 1 ? "1 ingredient added" : "\(pickedCount) ingredients added")
                    .font(.subheadline.weight(.medium))
                if let lastPicked {
                    Text(lastPicked)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: pickedCount)
    }

    /// Everything found, in its two groups. The products are ranked here rather than
    /// when they arrive, so a late answer lands in the right place rather than at the
    /// end of the list.
    private var sections: SearchResults.Sections {
        SearchResults.sections(
            local: local,
            database: database,
            products: products.records.map { SearchResult.make(product: $0, query: query) }
        )
    }

    /// A tapped row: a food is ready to go, a product found by name is not.
    private func select(_ result: SearchResult) {
        switch result.action {
        case .choice(let choice):
            present(choice)
        case .fetch(let record):
            Task { await choose(product: record) }
        }
    }

    /// In pick mode the choice goes straight back, and a multiple pick stays open with
    /// the field cleared and focused, so the next ingredient is one word away.
    /// Otherwise a bundled hit, which knows nothing of past use, gets `lastAmount` from
    /// its stored row before the Quantity sheet opens.
    private func present(_ choice: FoodChoice) {
        if case .pick(let multiple, let onPick) = mode {
            onPick(choice)
            guard multiple else {
                dismiss()
                return
            }
            pickedCount += 1
            lastPicked = choice.name
            searchText = ""
            fieldFocused = true
            return
        }
        var prepared = choice
        if let bundledID = choice.bundledID {
            do {
                if let food = try Food.bundled(id: bundledID, in: context) {
                    prepared = choice.with(lastAmount: food.lastGrams)
                }
            } catch {
                AppLog.store.error("food lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        sheet = .quantity(prepared)
    }

    /// Runs once a sheet is gone: a product typed from its label carries on as any
    /// other food would. Nothing is pending after a log, so this does nothing then.
    private func advance() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil
        present(choice)
    }

    /// A product from the search results. Its values are fetched by barcode through the
    /// same flow a scan uses, which caches it here for good; a product the fetch cannot
    /// answer for opens the editor with what the search did know, to type from the label.
    private func choose(product record: ProductRecord) async {
        let client = OpenFoodFactsClient(transport: URLSessionTransport(), userAgent: UserAgent.current())
        let flow = BarcodeLookupFlow(context: context, client: client)
        switch await flow.resolve(code: record.code) {
        case .found(let choice):
            present(choice)
        case .manual(let barcode, let prefillName, let measure, let reason):
            sheet = .product(ProductPrefill(
                barcode: barcode, name: prefillName ?? record.name, measure: measure, reason: reason
            ))
        }
    }

    /// An estimate was logged: Today gets the banner text and the screen closes.
    private func estimated(_ message: String) {
        if case .log(_, _, let onMessage) = mode {
            onMessage(message)
        }
        dismiss()
    }

    /// Debounced 150 ms; `.task(id:)` cancels the previous run on every keystroke. The
    /// Library is matched by name and tag on the main context, the database by FTS in
    /// its actor.
    private func search() async {
        let text = query
        guard isSearching else {
            local = []
            database = []
            databaseError = nil
            products.clear()
            return
        }
        try? await Task.sleep(for: Self.localDebounce)
        guard !Task.isCancelled else { return }
        local = localMatches(for: text)
        do {
            let found = try await foodRepository.search(text)
            guard !Task.isCancelled else { return }
            database = found.map { SearchResult.make(bundled: $0, query: text) }
            databaseError = nil
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.foodDB.error("search failed: \(error.localizedDescription, privacy: .private)")
            database = []
            databaseError = error.localizedDescription
        }
        await searchProducts(text)
    }

    /// The product half, which leaves the device, so it waits for the typist to stop
    /// and only asks about a query worth sending. The local results are already on
    /// screen by then; these arrive under them.
    ///
    /// Last query's products are cleared first: they are not results for this query,
    /// and showing Kinder Bueno under a search for cola is worse than showing nothing.
    private func searchProducts(_ text: String) async {
        products.isEnabled = productSearchEnabled
        guard productSearchEnabled, ProductResults.isWorthSearching(text) else {
            products.clear()
            return
        }
        // Cleared and immediately marked as searching, both before the wait: the last
        // query's products go at once, and the row that says more are coming stays put
        // across keystrokes instead of flickering, which also stops "no results"
        // appearing for a second before the products arrive to contradict it.
        products.clear()
        products.isSearching = true
        try? await Task.sleep(for: ProductResults.quietPeriod - Self.localDebounce)
        guard !Task.isCancelled else { return }
        let client = OpenFoodFactsClient(transport: URLSessionTransport(), userAgent: UserAgent.current())
        do {
            let found = try await client.products(matching: text)
            guard !Task.isCancelled else { return }
            products.records = found
            products.isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.barcode.error("product search failed: \(error.localizedDescription, privacy: .private)")
            products.records = []
            products.isSearching = false
            products.errorMessage = "Open Food Facts could not be reached."
        }
    }

    /// The Library half. Rows are built from the stored models rather than from their
    /// choices, because a recipe's tags are part of what it can be found by.
    private func localMatches(for text: String) -> [SearchResult] {
        do {
            let recipes = includesRecipes
                ? try LibrarySearch.recipes(matching: text, in: context)
                    .map { SearchResult.make(recipe: $0, query: text) }
                : []
            let foods = try LibrarySearch.foods(matching: text, in: context)
                .compactMap { SearchResult.make(food: $0, query: text) }
            return recipes + foods
        } catch {
            AppLog.store.error("library search failed: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }
}

#if DEBUG
#Preview("Log mode, recents") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Log mode, nothing logged yet") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .empty)
}

#Preview("Log mode, modules on") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .library, defaults: PreviewDefaults.modulesOn)
}

#Preview("Log mode, modules on, nothing logged yet") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .empty, defaults: PreviewDefaults.modulesOn)
}

#Preview("Picking one food") {
    FoodSearchView(mode: .pick(multiple: false, onPick: { _ in }))
        .previewEnvironment(seed: .library)
}

#Preview("Picking ingredients") {
    FoodSearchView(mode: .pick(multiple: true, onPick: { _ in }))
        .previewEnvironment(seed: .library)
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 768)) {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Log mode, accessibility 5") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
