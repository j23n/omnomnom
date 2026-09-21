import Foundation
import os
import SwiftData
import SwiftUI

/// Grams, portion chips, live preview, meal slot and time, then Confirm.
struct QuantitySheet: View {
    let choice: FoodChoice
    let onLogged: (LogResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.foodRepository) private var foodRepository

    @State private var gramsText: String
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    @State private var portions: [Portion] = []
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var gramsFocused: Bool

    /// - Parameter day: the day shown on Today; the entry defaults to that day at the current time.
    init(choice: FoodChoice, day: Date, onLogged: @escaping (LogResult) -> Void) {
        self.choice = choice
        self.onLogged = onLogged
        let timestamp = Self.defaultTimestamp(on: day)
        _timestamp = State(initialValue: timestamp)
        _mealSlot = State(initialValue: MealSlot.inferred(from: timestamp))
        _gramsText = State(initialValue: choice.lastGrams.map(Formatters.gramsFieldText) ?? "")
    }

    private var grams: Double? { Formatters.parseGrams(gramsText) }

    private var preview: Nutrition {
        SnapshotMath.snapshot(per100g: choice.per100g, grams: grams ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(choice.name)
                        .font(.headline)
                    GramField(text: $gramsText, isFocused: $gramsFocused)
                    if !gramsText.isEmpty, grams == nil {
                        Text("Enter between \(Formatters.gramsRangeText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    PortionChips(portions: portions) { portion in
                        gramsText = Formatters.gramsFieldText(portion.grams)
                    }
                }
                Section("Nutrition") {
                    NutritionPreview(nutrition: preview)
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
                    .disabled(grams == nil || isSaving)
                }
            }
            .task { await prepare() }
        }
    }

    private func prepare() async {
        do {
            portions = try await foodRepository.portions(for: choice.bundledID)
        } catch {
            AppLog.foodDB.error("portions failed: \(error.localizedDescription, privacy: .private)")
        }
        if gramsText.isEmpty, let first = portions.first {
            gramsText = Formatters.gramsFieldText(first.grams)
        }
        gramsFocused = true
    }

    private func confirm() async {
        guard let grams, !isSaving else { return }
        isSaving = true
        let logger = EntryLogger(context: context, health: health)
        do {
            let result = try await logger.log(choice: choice, grams: grams, mealSlot: mealSlot, at: timestamp)
            onLogged(result)
        } catch {
            AppLog.store.error("local save failed: \(error.localizedDescription, privacy: .public)")
            saveError = "Could not save: \(error.localizedDescription)"
            isSaving = false
        }
    }

    /// `day` at the current wall-clock time, so logging into the past keeps a sensible time.
    private static func defaultTimestamp(on day: Date, calendar: Calendar = .current) -> Date {
        let now = Date.now
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}
