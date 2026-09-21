import Foundation
import os
import SwiftData
import SwiftUI

/// What the Add sheet does with a tapped row.
enum AddFoodMode {
    /// Open the Quantity sheet for `day`; a completed log dismisses both sheets.
    case log(day: Date, onLogged: (LogResult) -> Void)
    /// Hand the choice back at once, as the recipe builder needs. Recipes are hidden.
    case pick(onPick: (FoodChoice) -> Void)
}

/// Search over the Library and the bundled database, with recents before any typing.
/// In log mode, and with the module on, a Scan button leads to the barcode flow.
struct AddFoodSheet: View {
    let mode: AddFoodMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var searchPresented = true
    @State private var local: [FoodChoice] = []
    @State private var results: [BundledFood] = []
    @State private var searchError: String?
    @State private var choice: FoodChoice?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var includesRecipes: Bool {
        if case .log = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    SearchResultsList(local: local, results: results, errorMessage: searchError) { present($0) }
                } else {
                    RecentsList(includesRecipes: includesRecipes) { present($0) }
                }
            }
            .navigationTitle(includesRecipes ? "Add food" : "Add ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Search foods")
            .task(id: searchText) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $choice) { choice in
                if case .log(let day, let onLogged) = mode {
                    QuantitySheet(choice: choice, day: day) { result in
                        self.choice = nil
                        onLogged(result)
                        dismiss()
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .modifier(BarcodeEntryPoint(isActive: includesRecipes) { present($0) })
        }
    }

    /// In pick mode the choice goes straight back. Otherwise a bundled hit, which knows
    /// nothing of past use, gets `lastAmount` from its stored row before the sheet opens.
    private func present(_ choice: FoodChoice) {
        if case .pick(let onPick) = mode {
            onPick(choice)
            dismiss()
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
