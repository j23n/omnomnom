import Foundation
import os
import SwiftData
import SwiftUI

/// Recipes, custom foods and scanned products, with the bundled database line that
/// says the app works offline out of the box. Rows open their editor; swiping deletes.
/// A deleted recipe takes its ingredient rows along; entries keep their snapshots.
///
/// Search matches a name or a tag, so typing "breakfast" answers with everything filed
/// under it, and the tag chips do the same in one tap.
struct LibraryView: View {
    @Environment(\.foodRepository) private var foodRepository
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query private var customFoods: [Food]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var foodCount: Int?
    @State private var errorMessage: String?
    @State private var deleteError: String?
    @State private var editor: LibraryEditor?
    @State private var searchText = ""
    @State private var selectedTag: String?

    init() {
        let custom = FoodKind.custom.rawValue
        let product = FoodKind.product.rawValue
        _customFoods = Query(filter: #Predicate<Food> { $0.kindRaw == custom || $0.kindRaw == product }, sort: \Food.name)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var isFiltering: Bool {
        !query.isEmpty || selectedTag != nil
    }

    private var shownRecipes: [Recipe] {
        recipes.filter { keep(name: $0.name, tags: $0.tags) }
    }

    private var shownFoods: [Food] {
        customFoods.filter { keep(name: $0.name, tags: $0.tags) }
    }

    /// A row survives the chip when it carries that tag, and the typed text when its
    /// name or one of its tags contains it.
    private func keep(name: String, tags: [Tag]?) -> Bool {
        let names = (tags ?? []).map(\.name)
        if let selectedTag, !names.contains(where: { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) {
            return false
        }
        guard !query.isEmpty else { return true }
        return name.localizedStandardContains(query)
            || names.contains { $0.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !tags.isEmpty {
                    Section {
                        FlowLayout(spacing: 8) {
                            ForEach(tags) { tag in
                                Button {
                                    selectedTag = selectedTag == tag.name ? nil : tag.name
                                } label: {
                                    Text(tag.name)
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedTag == tag.name ? Color.accentColor : Color.secondary)
                                .accessibilityAddTraits(selectedTag == tag.name ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                    }
                }
                Section("Recipes") {
                    if shownRecipes.isEmpty {
                        Text(isFiltering ? "No recipes match." : "No recipes yet. Add one with +.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shownRecipes) { recipe in
                        Button {
                            editor = .recipe(recipe)
                        } label: {
                            RecipeRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { shownRecipes[$0] }, what: "recipe") }
                }
                Section("Custom foods and products") {
                    if shownFoods.isEmpty {
                        Text(isFiltering ? "No foods match." : "No custom foods yet. Add one with +, or scan a product.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shownFoods) { food in
                        Button {
                            editor = .food(food)
                        } label: {
                            CustomFoodRow(food: food)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { shownFoods[$0] }, what: "custom food") }
                }
                if let deleteError {
                    Section {
                        Text(deleteError)
                            .foregroundStyle(.secondary)
                    }
                }
                if !isFiltering {
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
            }
            .composingTab()
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search names and tags")
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
            .onChange(of: tags.map(\.name)) { _, names in
                // A tag can go when its last use does; the chip must not linger selected.
                if let selectedTag, !names.contains(selectedTag) {
                    self.selectedTag = nil
                }
            }
        }
    }

    private func loadCount() async {
        do {
            foodCount = try await foodRepository.foodCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the rows and saves; a failure is logged and shown above the database
    /// line. A tag whose last use went with them goes too.
    private func delete<T: PersistentModel>(_ models: [T], what: String) {
        for model in models {
            context.delete(model)
        }
        do {
            try Tag.removeOrphans(in: context)
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
