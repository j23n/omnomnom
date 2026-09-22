import Foundation
import os
import SwiftData
import SwiftUI

/// Grams (or servings for a recipe), shortcut chips, live preview, meal slot and time,
/// then Log. The entry always stores raw grams; a recipe entry stores servings too.
/// A product fetched from Open Food Facts carries its attribution under the preview.
struct QuantitySheet: View {
    let choice: FoodChoice
    let onLogged: (LogResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.foodRepository) private var foodRepository

    @State private var amountText: String
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    @State private var chips: [AmountChip]
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var amountFocused: Bool

    /// - Parameter day: the day shown on Today; the entry defaults to that day at the current time.
    init(choice: FoodChoice, day: Date, onLogged: @escaping (LogResult) -> Void) {
        self.choice = choice
        self.onLogged = onLogged
        let timestamp = Self.defaultTimestamp(on: day)
        _timestamp = State(initialValue: timestamp)
        _mealSlot = State(initialValue: MealSlot.inferred(from: timestamp))
        _chips = State(initialValue: choice.isRecipe ? AmountChip.servings : [])
        let prefill: Double? = choice.lastAmount ?? (choice.isRecipe ? 1.0 : nil)
        _amountText = State(initialValue: prefill.map(Formatters.fieldText) ?? "")
    }

    private var amount: Double? {
        (choice.isRecipe ? AmountUnit.servings : AmountUnit.grams).parse(amountText)
    }

    private var preview: Nutrition {
        choice.snapshot(for: amount ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                AmountSection(choice: choice, chips: chips, text: $amountText, isFocused: $amountFocused)
                Section {
                    NutritionPreview(nutrition: preview)
                    if choice.isRecipe {
                        LabeledContent("Raw weight", value: Formatters.grams(choice.grams(for: amount ?? 0)))
                    }
                } header: {
                    Text("Nutrition")
                } footer: {
                    OpenFoodFactsAttribution(attribution: choice.attribution)
                }
                Section {
                    Picker("Meal", selection: $mealSlot) {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Text(slot.displayName).tag(slot)
                        }
                    }
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task { await confirm() }
                    }
                    .disabled(amount == nil || isSaving)
                }
            }
            .task { await prepare() }
        }
    }

    /// Loads the portion chips of a bundled food and, absent a last amount, prefills the first.
    private func prepare() async {
        if let bundledID = choice.bundledID {
            do {
                let portions = try await foodRepository.portions(for: bundledID)
                chips = AmountChip.portions(portions)
                if amountText.isEmpty, let first = portions.first {
                    amountText = Formatters.fieldText(first.grams)
                }
            } catch {
                AppLog.foodDB.error("portions failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        amountFocused = true
    }

    private func confirm() async {
        guard let amount, !isSaving else { return }
        isSaving = true
        let logger = EntryLogger(context: context, health: health)
        do {
            let result = try await logger.log(choice: choice, amount: amount, mealSlot: mealSlot, at: timestamp)
            onLogged(result)
        } catch {
            AppLog.store.error("local save failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save: \(error.localizedDescription)"
            isSaving = false
        }
    }

    /// `day` at the current wall-clock time, so logging into the past keeps a sensible time.
    /// Shared with the estimation draft, which defaults its entries the same way.
    static func defaultTimestamp(on day: Date, calendar: Calendar = .current) -> Date {
        let now = Date.now
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

// Portion chips come from the bundled database; when `foods.sqlite` is not in the bundle
// (the pipeline has not run on this Mac) the bundled preview shows no chips.

#if DEBUG
#Preview("Bundled food with portions") {
    QuantitySheet(choice: PreviewStore.bundledChoice, day: .now) { _ in }
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Custom food") {
    QuantitySheet(choice: PreviewStore.customChoice, day: .now) { _ in }
        .previewEnvironment(seed: .library)
}

#Preview("Recipe, servings") {
    QuantitySheet(choice: PreviewStore.recipeChoice, day: .now) { _ in }
        .previewEnvironment(seed: .library)
}

#Preview("Product with attribution") {
    QuantitySheet(choice: PreviewStore.productChoice, day: .now) { _ in }
        .previewEnvironment(seed: .library)
}

#Preview("Accessibility 5") {
    QuantitySheet(choice: PreviewStore.recipeChoice, day: .now) { _ in }
        .previewEnvironment(seed: .library)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Bundled with last amount") {
    QuantitySheet(choice: PreviewStore.bundledChoice.with(lastAmount: 182), day: .now) { _ in }
        .previewEnvironment(seed: .typicalDay)
}
#endif
