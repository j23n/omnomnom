import Foundation
import os
import SwiftData
import SwiftUI

/// The estimate as editable rows, the totals, the meal slot and time, then Log. Nothing
/// reaches the store or Health until the button is tapped; every value can be changed
/// or the row removed first.
struct EstimateDraftView: View {
    let day: Date
    let onLogged: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health

    @State private var draft: EstimateDraft
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    @State private var isSaving = false
    @State private var saveError: String?

    /// - Parameter day: the day shown on Today; the entries default to that day at the current time.
    init(draft: EstimateDraft, day: Date, onLogged: @escaping (String) -> Void) {
        self.day = day
        self.onLogged = onLogged
        _draft = State(initialValue: draft)
        let timestamp = QuantitySheet.defaultTimestamp(on: day)
        _timestamp = State(initialValue: timestamp)
        _mealSlot = State(initialValue: MealSlot.inferred(from: timestamp))
    }

    private var logTitle: String {
        let count = draft.rows.count
        return count == 1 ? "Log 1 item" : "Log \(count) items"
    }

    var body: some View {
        Form {
            if !draft.note.isEmpty || !draft.warnings.isEmpty {
                Section("Assumptions") {
                    if !draft.note.isEmpty {
                        Text(draft.note)
                    }
                    ForEach(draft.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach($draft.rows) { $row in
                    EstimateDraftRowView(row: $row) { draft.remove(id: row.id) }
                }
            } header: {
                Text("Items")
            } footer: {
                Text("Values are for the portion. Blank means unknown.")
            }
            Section("Totals") {
                NutritionPreview(nutrition: draft.totals)
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
        .navigationTitle("Check the estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(logTitle) {
                    Task { await log() }
                }
                .disabled(draft.items == nil || isSaving)
            }
        }
    }

    private func log() async {
        guard let items = draft.items, !isSaving else { return }
        isSaving = true
        let logger = EstimateLogger(context: context, health: health)
        do {
            let outcome = try await logger.log(items, mealSlot: mealSlot, at: timestamp)
            onLogged(outcome.bannerMessage)
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

#if DEBUG
#Preview("Three items, one warning") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.draft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Dark") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.draft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
    .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.draft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Invalid row, Log disabled") {
    var draft = PreviewEstimates.draft
    draft.rows[1].gramsText = ""
    return NavigationStack {
        EstimateDraftView(draft: draft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
}
#endif
