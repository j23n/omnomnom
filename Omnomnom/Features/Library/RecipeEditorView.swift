import Foundation
import os
import SwiftData
import SwiftUI

/// Builds or edits one recipe on a value-type draft. Done applies the draft to the
/// model; Cancel discards it. Ingredients come from the Add sheet in pick mode.
struct RecipeEditorView: View {
    /// The recipe being edited, or `nil` to create one.
    let recipe: Recipe?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: RecipeDraft
    @State private var isPicking = false
    @State private var saveError: String?

    init(recipe: Recipe?) {
        self.recipe = recipe
        _draft = State(initialValue: recipe.map { RecipeWriter.draft(of: $0) } ?? RecipeDraft())
    }

    private var hasLoggedEntries: Bool {
        !(recipe?.entries ?? []).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    Stepper(value: $draft.servings, in: RecipeDraft.minimumServings...RecipeDraft.maximumServings, step: 0.5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Formatters.servings(draft.servings))
                            Text("= \(Formatters.grams(draft.gramsPerServing)) raw per serving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Servings are portions of the raw total, not of the cooked weight.")
                }
                PhotoPickerSection(photo: $draft.photo, footer: "Shown with the recipe and every entry logged from it.")
                Section {
                    ForEach($draft.ingredients) { $ingredient in
                        IngredientRow(ingredient: $ingredient)
                    }
                    .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.ingredients.remove(atOffsets: $0) }
                    Button("Add ingredient", systemImage: "plus") { isPicking = true }
                } header: {
                    HStack {
                        Text("Ingredients")
                        Spacer()
                        EditButton()
                    }
                } footer: {
                    Text("Raw total \(Formatters.grams(draft.totalWeight))")
                }
                Section("Per serving") {
                    NutritionPreview(nutrition: draft.perServing)
                }
                if hasLoggedEntries {
                    Section {
                        Text("Previously logged servings are unchanged.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .sheet(isPresented: $isPicking) {
                AddFoodSheet(mode: .pick(onPick: { draft.add($0) }))
            }
        }
    }

    private func save() {
        do {
            try RecipeWriter(context: context).write(draft, into: recipe)
            dismiss()
        } catch {
            AppLog.store.error("recipe save failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("New recipe") {
    RecipeEditorView(recipe: nil)
        .previewEnvironment(seed: .library)
}

#Preview("Editing a logged recipe") {
    // The lentil soup has been logged once, so the "previously logged" footnote shows.
    let container = PreviewStore.container(seed: .library)
    let recipe = PreviewStore.recipes(in: container).first { !($0.entries ?? []).isEmpty }
    return RecipeEditorView(recipe: recipe)
        .previewEnvironment(container: container)
}

#Preview("Editing a recipe with a photo") {
    let container = PreviewStore.container(seed: .library)
    let recipe = PreviewStore.recipes(in: container).first { $0.photo != nil }
    return RecipeEditorView(recipe: recipe)
        .previewEnvironment(container: container)
}

#Preview("Editing, accessibility 5") {
    let container = PreviewStore.container(seed: .library)
    let recipe = PreviewStore.recipes(in: container).first
    return RecipeEditorView(recipe: recipe)
        .previewEnvironment(container: container)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
