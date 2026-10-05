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
///
/// In log mode every row carries a plus, which puts that food in the tray and leaves the
/// screen where it is. Tapping the row itself still opens the Quantity sheet and logs the
/// one food, as it always did — until a tray has been started, after which a tap adds to it
/// too, because one rule has to hold while a tray is up: nothing is logged until Log is
/// tapped. Logging four foods used to mean opening this screen four times.
struct FoodSearchView: View {
    let mode: AddFoodMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health

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
    /// The foods gathered to be logged together, as the line they amount to; `nil` until
    /// the first one goes in. In log mode only: a pick hands its food straight back.
    @State private var tray: LineResolution?
    /// Whether the tray's own screen is up, where the amounts are set.
    @State private var isReviewing = false
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

    /// Whether this screen gathers foods before logging them, which is log mode and only
    /// log mode: a pick hands its food back to whatever asked for it.
    private var collects: Bool {
        logDay != nil
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
                        onAdd: collects ? { collect($0) } : nil,
                        onSelect: { select($0) }
                    )
                } else {
                    RecentsList(
                        includesRecipes: includesRecipes,
                        modules: modules,
                        onAdd: collects ? { collect($0) } : nil,
                        onSelect: { select($0) }
                    )
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
                } else if let tray {
                    TrayBar(tray: tray, onReview: { isReviewing = true }, onLog: logGathered)
                }
            }
            .sheet(isPresented: $isReviewing) {
                if let tray, let day = logDay {
                    NavigationStack {
                        ResolutionScreen(
                            resolution: tray,
                            day: day,
                            onChange: { self.tray?.replace($0) },
                            onRemove: { drop($0) },
                            onAdd: { self.tray?.append($0) },
                            onLog: { slot, at in Task { await logTray(mealSlot: slot, at: at) } }
                        )
                        // Presented rather than pushed, because the search screen it
                        // would be pushed onto is itself what the tray's own Add a food
                        // puts up. Its way out has to come from here: the screen was
                        // written to be the top of a stack and so carries no Back of its
                        // own, and leaving it must not log anything.
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Back") { isReviewing = false }
                            }
                        }
                    }
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
    ///
    /// Once a tray has been started, tapping a row puts the food in it rather than opening
    /// the Quantity sheet. One rule holds while the tray is up — nothing is logged until
    /// Log is tapped — and the alternative was a sheet that logged one food and closed the
    /// screen on four others the user had gathered.
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
        let prepared = remembered(choice)
        guard tray == nil else {
            collect(prepared)
            return
        }
        sheet = .quantity(prepared)
    }

    /// Puts a row's food in the tray and leaves the screen where it is, with the field
    /// cleared for the next one.
    private func collect(_ result: SearchResult) {
        guard case .choice(let choice) = result.action else { return }
        collect(remembered(choice))
    }

    /// The same, for a food that is already in hand.
    ///
    /// The amount is what this person last had of it, which is the only honest default and
    /// the one the steps on the tray's screen then measure from; a food they have never had
    /// starts at 100 of its own unit, or one serving of a recipe, and no steps are offered
    /// for it. Everything in a tray is `chosen` and settled: nobody guessed any of it.
    private func collect(_ choice: FoodChoice) {
        let row = ResolvedRow(
            name: choice.name,
            choice: choice,
            amount: choice.lastAmount ?? (choice.isRecipe ? 1 : EntryLogger.defaultAmount),
            baseAmount: choice.lastAmount,
            origin: .chosen,
            confidence: .settled
        )
        if tray == nil {
            // No line behind it, and the key a phrase is remembered under is made from a
            // line: a tray teaches the app nothing, which is right. Nobody said anything.
            tray = LineResolution(line: "", rows: [row], wasChecked: false)
        } else {
            tray?.append(row)
        }
        searchText = ""
        fieldFocused = true
    }

    /// Takes a food out of the tray, and closes the tray's screen with the last of them.
    private func drop(_ row: ResolvedRow) {
        tray?.remove(row)
        if tray?.rows.isEmpty ?? true {
            tray = nil
            isReviewing = false
        }
    }

    /// Logs the tray where it stands, into the meal this hour implies on the day being
    /// looked at. The tray's own screen is where another meal or another time is chosen.
    private func logGathered() {
        guard let day = logDay else { return }
        let slot = MealSlot.inferred(from: QuantitySheet.defaultTimestamp(on: day))
        Task { await logTray(mealSlot: slot, at: slot.timestamp(on: day)) }
    }

    /// Logs everything in the tray, into one meal at one time.
    ///
    /// Through `logLine`, which is the same path a typed line takes, so there is one way a
    /// row of foods reaches Health rather than two. Nothing is remembered as a phrase: the
    /// line is empty because there was no line, and `Phrase.remember` wants a key it can
    /// normalise from one.
    ///
    /// No undo is offered afterwards, and none is owed. Log is the sign-off here — that is
    /// what the tray is for — where a typed line is written without one and needs the way
    /// back that `LoggedLine` gives it.
    private func logTray(mealSlot: MealSlot, at timestamp: Date) async {
        guard let gathered = tray else { return }
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(gathered, mealSlot: mealSlot, at: timestamp, origin: .picked)
        tray = nil
        isReviewing = false
        if case .log(_, _, let onMessage) = mode {
            onMessage(LoggedLine(resolution: gathered, outcome: outcome).message)
        }
        dismiss()
    }

    /// A bundled hit knows nothing of past use, so what this person last had of it comes
    /// from its stored row. Everything else already carries it.
    private func remembered(_ choice: FoodChoice) -> FoodChoice {
        guard let bundledID = choice.bundledID else { return choice }
        do {
            if let food = try Food.bundled(id: bundledID, in: context) {
                return choice.with(lastAmount: food.lastGrams)
            }
        } catch {
            AppLog.store.error("food lookup failed: \(error.localizedDescription, privacy: .public)")
        }
        return choice
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
