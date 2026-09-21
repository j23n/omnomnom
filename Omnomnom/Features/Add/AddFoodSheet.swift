import Foundation
import os
import SwiftData
import SwiftUI

/// Search over the bundled database with recents shown before any typing.
/// Picking a food opens the Quantity sheet; a completed log dismisses both.
struct AddFoodSheet: View {
    let day: Date
    let onLogged: (LogResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var searchPresented = true
    @State private var results: [BundledFood] = []
    @State private var searchError: String?
    @State private var choice: FoodChoice?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    SearchResultsList(results: results, errorMessage: searchError) { present($0) }
                } else {
                    RecentsList { choice = $0 }
                }
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Search foods")
            .task(id: searchText) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $choice) { choice in
                QuantitySheet(choice: choice, day: day) { result in
                    self.choice = nil
                    onLogged(result)
                    dismiss()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// A search hit knows nothing of past use; fill in `lastGrams` from the stored row, if any.
    private func present(_ choice: FoodChoice) {
        do {
            if let food = try Food.bundled(id: choice.bundledID, in: context) {
                self.choice = choice.with(lastGrams: food.lastGrams)
                return
            }
        } catch {
            AppLog.store.error("food lookup failed: \(error.localizedDescription, privacy: .public)")
        }
        self.choice = choice
    }

    /// Debounced 150 ms; `.task(id:)` cancels the previous run on every keystroke.
    private func search() async {
        let text = searchText
        guard isSearching else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
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
}
