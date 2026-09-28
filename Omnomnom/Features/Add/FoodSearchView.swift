import Foundation
import os
import SwiftData
import SwiftUI

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

/// A screen for finding a food: the Library and the bundled database under one search
/// field, with recents before any typing. In log mode, and with the module on, a Scan
/// button leads to the barcode flow and an Estimate button to on-device estimation.
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
    @State private var local: [FoodChoice] = []
    @State private var results: [BundledFood] = []
    @State private var searchError: String?
    @State private var choice: FoodChoice?
    @State private var scanRequested = false
    @State private var estimateRequested = false
    /// How many foods have gone back to the caller in a multiple pick, and the last of
    /// them, so the bottom bar can say what happened without anything else moving.
    @State private var pickedCount = 0
    @State private var lastPicked: String?
    @FocusState private var fieldFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
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
                    SearchResultsList(local: local, results: results, errorMessage: searchError, modules: modules) {
                        present($0)
                    }
                } else {
                    RecentsList(includesRecipes: includesRecipes, modules: modules) { present($0) }
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
            .sheet(item: $choice) { choice in
                if case .log(let day, let onLogged, _) = mode {
                    QuantitySheet(choice: choice, day: day) { result in
                        self.choice = nil
                        onLogged(result)
                        dismiss()
                    }
                    .presentationDetents([.medium, .large])
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
        self.choice = prepared
    }

    /// An estimate was logged: Today gets the banner text and the screen closes.
    private func estimated(_ message: String) {
        if case .log(_, _, let onMessage) = mode {
            onMessage(message)
        }
        dismiss()
    }

    /// Debounced 150 ms; `.task(id:)` cancels the previous run on every keystroke. The
    /// Library is matched by name on the main context, the database by FTS in its actor.
    private func search() async {
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard isSearching else {
            local = []
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        local = localMatches(for: text)
        do {
            let found = try await foodRepository.search(text)
            guard !Task.isCancelled else { return }
            results = found
            searchError = nil
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.foodDB.error("search failed: \(error.localizedDescription, privacy: .private)")
            results = []
            searchError = error.localizedDescription
        }
    }

    private func localMatches(for text: String) -> [FoodChoice] {
        do {
            let foods = try Food.libraryMatching(text, in: context).compactMap(\.choice)
            let recipes = includesRecipes ? try Recipe.matching(text, in: context).map(\.choice) : []
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

#Preview("Log mode, accessibility 5") {
    FoodSearchView(mode: .log(day: .now, onLogged: { _ in }, onMessage: { _ in }))
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
