import Foundation
import os
import SwiftData
import SwiftUI

/// Recipes, custom foods and scanned products, with the bundled database line that
/// says the app works offline out of the box. Rows open their editor; swiping deletes.
/// A deleted recipe takes its ingredient rows along; entries keep their snapshots.
struct LibraryView: View {
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query private var customFoods: [Food]
    @State private var foodCount: Int?
    @State private var errorMessage: String?
    @State private var deleteError: String?
    @State private var editor: LibraryEditor?

    init() {
        let custom = FoodKind.custom.rawValue
        let product = FoodKind.product.rawValue
        _customFoods = Query(filter: #Predicate<Food> { $0.kindRaw == custom || $0.kindRaw == product }, sort: \Food.name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Recipes") {
                    if recipes.isEmpty {
                        Text("No recipes yet. Add one with +.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recipes) { recipe in
                        Button {
                            editor = .recipe(recipe)
                        } label: {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { recipes[$0] }, what: "recipe") }
                }
                Section("Custom foods and products") {
                    if customFoods.isEmpty {
                        Text("No custom foods yet. Add one with +, or scan a product.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(customFoods) { food in
                        Button {
                            editor = .food(food)
                        } label: {
                            CustomFoodRow(food: food)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { customFoods[$0] }, what: "custom food") }
                }
                if let deleteError {
                    Section {
                        Text(deleteError)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Bundled database") {
                    if let foodCount {
                        Text("Bundled database ready: \(foodCount) foods")
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Checking the bundled database…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New recipe", systemImage: "list.bullet.rectangle") { editor = .recipe(nil) }
                        Button("New custom food", systemImage: "carrot") { editor = .food(nil) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { editor in
                switch editor {
                case .recipe(let recipe): RecipeEditorView(recipe: recipe)
                case .food(let food): CustomFoodEditorView(food: food)
                }
            }
            .task { await loadCount() }
        }
    }

    private func loadCount() async {
        do {
            foodCount = try await foodRepository.foodCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the rows and saves; a failure is logged and shown above the database line.
    private func delete<T: PersistentModel>(_ models: [T], what: String) {
        for model in models {
            context.delete(model)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.store.error("could not delete \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            deleteError = "Could not delete the \(what): \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("Library") {
    LibraryView()
        .previewEnvironment(seed: .library)
}

#Preview("Empty") {
    LibraryView()
        .previewEnvironment(seed: .empty)
}

#Preview("Accessibility 5") {
    LibraryView()
        .previewEnvironment(seed: .library)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
