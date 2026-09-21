import Foundation
import os
import SwiftData
import SwiftUI

/// Creates or edits a custom food: a name and per-100 g values, energy required.
/// Done stores the draft; Cancel discards it. Logged entries keep their snapshots.
struct CustomFoodEditorView: View {
    /// The food being edited, or `nil` to create one.
    let food: Food?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: CustomFoodDraft
    @State private var saveError: String?

    init(food: Food?) {
        self.food = food
        _draft = State(initialValue: food.map { CustomFoodDraft(name: $0.name, per100g: $0.per100g) } ?? CustomFoodDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        NutrientField(nutrient: nutrient, draft: $draft)
                    }
                } header: {
                    Text("Per 100 g")
                } footer: {
                    Text("Energy is required. Leave a value blank when it is not known; it is then not written to Health.")
                }
                if food != nil {
                    Section {
                        Text("Previously logged entries are unchanged.")
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
            .navigationTitle(food == nil ? "New custom food" : "Edit custom food")
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
        }
    }

    private func save() {
        guard let per100g = draft.per100g else { return }
        if let food {
            food.name = draft.trimmedName
            food.per100g = per100g
        } else {
            context.insert(Food(name: draft.trimmedName, kind: .custom, bundledID: nil, per100g: per100g))
        }
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            AppLog.store.error("custom food save failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }
}

/// One per-100 g field with its unit; energy is marked as required in the placeholder.
private struct NutrientField: View {
    let nutrient: Nutrient
    @Binding var draft: CustomFoodDraft

    private var text: Binding<String> {
        Binding(
            get: { draft.text(for: nutrient) },
            set: { draft.setText($0, for: nutrient) }
        )
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(nutrient == .energy ? "required" : "unknown", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(draft.isInvalid(nutrient) ? Color.red : Color.primary)
                    .accessibilityLabel("\(nutrient.displayName) per 100 grams, in \(nutrient.unit.symbol)")
                Text(nutrient.unit.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(nutrient.displayName)
        }
    }
}
