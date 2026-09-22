import Foundation
import os
import SwiftData
import SwiftUI

/// What the barcode flow hands the editor after a miss: the code to store on the new
/// product, the name when Open Food Facts had one, the unit its label counts in, and
/// the sentence saying why. The unit is `mass` when nothing was found to say otherwise,
/// which is where a food typed from scratch starts too.
nonisolated struct ProductPrefill: Hashable, Sendable {
    let barcode: String
    let name: String?
    let measure: FoodMeasure
    let reason: String
}

/// Creates or edits a custom food, or creates a product typed from its label after a
/// barcode miss: a name, the unit it is measured in, and per-100 values in that unit,
/// energy required. Done stores the draft; Cancel discards it. Logged entries keep
/// their snapshots, and the unit is fixed once there are any.
struct CustomFoodEditorView: View {
    /// The food being edited, or `nil` to create one.
    let food: Food?
    /// Set when creating a product from a barcode; the saved food is then kind `product`.
    let product: ProductPrefill?
    /// Receives the saved food before the sheet closes, so a flow can carry on with it.
    let onSaved: ((Food) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: CustomFoodDraft
    @State private var saveError: String?

    init(food: Food?, product: ProductPrefill? = nil, onSaved: ((Food) -> Void)? = nil) {
        self.food = food
        self.product = product
        self.onSaved = onSaved
        var draft = food.map {
            CustomFoodDraft(name: $0.name, per100g: $0.per100g, measure: $0.measure, photo: $0.photo?.data)
        } ?? CustomFoodDraft()
        if food == nil, let product {
            draft.measure = product.measure
            if let name = product.name {
                draft.name = name
            }
        }
        _draft = State(initialValue: draft)
    }

    private var title: String {
        if product != nil { return "New product" }
        if let food { return food.kind == .product ? "Edit product" : "Edit custom food" }
        return "New custom food"
    }

    /// Whether the unit is fixed: changing it under logged entries would silently
    /// reinterpret their amounts, and those entries are a record, not a reference.
    private var isMeasureLocked: Bool {
        !(food?.entries ?? []).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let product {
                    Section {
                        Text(product.reason)
                        LabeledContent("Barcode", value: product.barcode)
                    }
                }
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    Picker("Measured in", selection: $draft.measure) {
                        ForEach(FoodMeasure.allCases, id: \.self) { measure in
                            Text(measure.displayName).tag(measure)
                        }
                    }
                    .disabled(isMeasureLocked)
                } footer: {
                    if isMeasureLocked {
                        Text("The unit stays as it is: entries already logged are counted in it.")
                    }
                }
                Section {
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        NutrientField(nutrient: nutrient, draft: $draft)
                    }
                } header: {
                    Text(
                        product == nil
                            ? "Per \(draft.measure.referenceUnit)"
                            : "Type the values from the label, \(draft.measure.referenceText)"
                    )
                } footer: {
                    Text("Energy is required. Leave a value blank when it is not known; it is then not written to Health.")
                }
                PhotoPickerSection(photo: $draft.photo, footer: "Shown with the food and every entry logged from it.")
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
            .navigationTitle(title)
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

    /// Updates the food in place or inserts a new one: a custom food, or a product with
    /// its barcode and source `manual` when the editor was opened from the scanner.
    /// Editing a product fetched from Open Food Facts also switches its source to
    /// `manual`: the values are the user's now, so the badge and attribution go. The
    /// unit follows the draft only while nothing has been logged from the food. The
    /// photo is created, replaced or deleted to match the draft.
    private func save() {
        guard let per100g = draft.per100g else { return }
        let saved: Food
        if let food {
            food.name = draft.trimmedName
            food.per100g = per100g
            if !isMeasureLocked {
                food.measure = draft.measure
            }
            if food.kind == .product {
                food.source = .manual
                food.fetchedAt = nil
            }
            saved = food
        } else {
            saved = Food(
                name: draft.trimmedName, kind: product == nil ? .custom : .product,
                bundledID: nil, per100g: per100g, measure: draft.measure
            )
            if let product {
                saved.barcode = product.barcode
                saved.source = .manual
            }
            context.insert(saved)
        }
        saved.photo = Photo.replacing(saved.photo, with: draft.photo, in: context)
        do {
            try context.save()
            onSaved?(saved)
            dismiss()
        } catch {
            context.rollback()
            AppLog.store.error("custom food save failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview("New custom food") {
    CustomFoodEditorView(food: nil)
        .previewEnvironment(seed: .library)
}

#Preview("Editing a custom food") {
    let container = PreviewStore.container(seed: .library)
    let food = PreviewStore.food(in: container, kind: .custom)
    return CustomFoodEditorView(food: food)
        .previewEnvironment(container: container)
}

#Preview("Editing a custom food with a photo") {
    let container = PreviewStore.container(seed: .library)
    let food = PreviewStore.foods(in: container).first { $0.photo != nil }
    return CustomFoodEditorView(food: food)
        .previewEnvironment(container: container)
}

#Preview("Editing a product") {
    let container = PreviewStore.container(seed: .library)
    let food = PreviewStore.food(in: container, kind: .product)
    return CustomFoodEditorView(food: food)
        .previewEnvironment(container: container)
}

#Preview("Product from a barcode miss") {
    CustomFoodEditorView(
        food: nil,
        product: ProductPrefill(barcode: "4006381333931", name: nil, measure: .mass, reason: "Not on Open Food Facts")
    )
    .previewEnvironment(seed: .library)
}

#Preview("Product with a name but no values") {
    CustomFoodEditorView(
        food: nil,
        product: ProductPrefill(
            barcode: "8710340000104", name: "Crunchy muesli", measure: .mass,
            reason: "No nutrition values on Open Food Facts"
        )
    )
    .previewEnvironment(seed: .library)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Drink from a barcode miss") {
    CustomFoodEditorView(
        food: nil,
        product: ProductPrefill(
            barcode: "7394376616105", name: "Oat drink", measure: .volume,
            reason: "No nutrition values on Open Food Facts"
        )
    )
    .previewEnvironment(seed: .library)
}
#endif
