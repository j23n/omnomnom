import Foundation
import os
import SwiftData
import SwiftUI

/// Builds or edits one recipe on a value-type draft. Done applies the draft to the
/// model; Cancel discards it. Ingredients come from the food search screen in pick mode.
///
/// A `draft` may be handed in instead of a recipe, which is how an estimate becomes a
/// recipe: the rows arrive filled in and the user only names and divides them.
struct RecipeEditorView: View {
    /// The recipe being edited, or `nil` to create one.
    let recipe: Recipe?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: RecipeDraft
    @State private var isPicking = false
    @State private var saveError: String?

    init(recipe: Recipe?, draft: RecipeDraft? = nil) {
        self.recipe = recipe
        _draft = State(initialValue: draft ?? recipe.map { RecipeWriter.draft(of: $0) } ?? RecipeDraft())
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
                            // Nothing to divide until a row parses, and a serving of
                            // nothing has no unit to print it in.
                            if !draft.amountPerServing.isEmpty {
                                Text("= \(draft.amountPerServing.text) raw per serving")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Servings are portions of the raw total, not of the cooked weight.")
                }
                PhotoPickerSection(photo: $draft.photo, footer: "Shown on every entry logged from this recipe.")
                TagSection(tags: $draft.tags)
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
                    Text(draft.totalAmount.isEmpty ? "No raw total yet" : "Raw total \(draft.totalAmount.text)")
                }
                Section("Per serving") {
                    NutritionPreview(nutrition: draft.perServing)
                }
                EditorNotes(
                    loggedNote: hasLoggedEntries ? "Previously logged servings are unchanged." : nil,
                    saveError: saveError
                )
            }
            .editorToolbar(
                title: recipe == nil ? "New recipe" : "Edit recipe", isValid: draft.isValid
            ) { save() }
            .fullScreenCover(isPresented: $isPicking) {
                FoodSearchView(mode: .pick(multiple: true, onPick: { draft.add($0) }))
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

/// One ingredient in the builder: name and its energy, with the amount field inline in
/// the food's own unit, grams or millilitres.
struct IngredientRow: View {
    @Binding var ingredient: IngredientDraft

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                Text(Formatters.amount(ingredient.energy, unit: .kilocalorie))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            Spacer()
            TextField("0", text: $ingredient.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .foregroundStyle(ingredient.amount == nil ? Color.red : Color.primary)
                .accessibilityLabel("\(ingredient.measure.displayName) of \(ingredient.name)")
                .accessibilityValue(
                    ingredient.amountText.isEmpty
                        ? "no amount"
                        : "\(ingredient.amountText) \(ingredient.measure.spokenName)"
                )
            Text(ingredient.measure.unitSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
