import Foundation
import os
import SwiftData
import SwiftUI

/// The estimate as rows to check, the totals, the meal slot and time, then Log. Every
/// value comes from the food on its row, which can be changed or the row removed; a row
/// without a food cannot be logged at all. Nothing reaches the store or Health until the
/// button is tapped. When the estimate came from a photo, a toggle decides whether the
/// photo is kept with the entries; it is on by default.
struct EstimateDraftView: View {
    let day: Date
    /// The stored-size photo the estimate was made from; `nil` for a text estimate.
    let photo: Data?
    let onLogged: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health

    @State private var draft: EstimateDraft
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    @State private var keepsPhoto = true
    @State private var isSaving = false
    @State private var saveError: String?
    /// The row whose food is being chosen; the sheet lives here so only one is ever open.
    @State private var picking: EstimateDraftRow?

    /// - Parameter day: the day shown on Today; the entries default to that day at the current time.
    init(draft: EstimateDraft, day: Date, photo: Data? = nil, onLogged: @escaping (String) -> Void) {
        self.day = day
        self.photo = photo
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
            if !draft.note.isEmpty {
                Section("Assumptions") {
                    Text(draft.note)
                }
            }
            Section {
                ForEach($draft.rows) { $row in
                    EstimateDraftRowView(
                        row: $row,
                        onChooseFood: { picking = row },
                        onRemove: { draft.remove(id: row.id) }
                    )
                }
            } header: {
                Text("Items")
            } footer: {
                if draft.hasUnmatchedRows {
                    Text("A row without a food cannot be logged. Choose one, or remove the row.")
                } else {
                    Text("Every value comes from the food on the row, for the portion you enter.")
                }
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
                if photo != nil {
                    Toggle(isOn: $keepsPhoto) {
                        HStack(spacing: 12) {
                            PhotoThumbnail(data: photo, size: 44)
                            Text("Keep photo")
                        }
                    }
                }
            } footer: {
                if photo != nil {
                    Text("Kept with these entries on this device. Never sent to Health.")
                }
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
        .sheet(item: $picking) { row in
            AddFoodSheet(mode: .pick(onPick: { choose($0, for: row.id) }))
        }
    }

    /// The picked food becomes the row's source of values; the portion is left as typed.
    /// A recipe is refused: the row's number is grams, which a recipe would read as
    /// servings. The Add sheet hides recipes in pick mode, so this is belt and braces.
    private func choose(_ choice: FoodChoice, for rowID: UUID) {
        guard !choice.isRecipe else { return }
        guard let index = draft.rows.firstIndex(where: { $0.id == rowID }) else { return }
        draft.rows[index].choice = choice
    }

    /// Rows are saved one by one, so a row that failed leaves the ones before it in the
    /// store. Whatever was logged is dropped from the draft before anything is shown, so
    /// tapping Log again can only log what is left. The screen closes once nothing is.
    private func log() async {
        guard let items = draft.items, !isSaving else { return }
        isSaving = true
        let logger = EstimateLogger(context: context, health: health)
        do {
            let outcome = try await logger.log(items, mealSlot: mealSlot, at: timestamp, photo: keepsPhoto ? photo : nil)
            let logged = Set(outcome.loggedRowIDs)
            draft.rows.removeAll { logged.contains($0.id) }
            if draft.rows.isEmpty {
                onLogged(outcome.bannerMessage)
            } else {
                saveError = outcome.bannerMessage
                isSaving = false
            }
        } catch {
            saveError = "Could not save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

#if DEBUG
/// Resolves a fixed estimate against the injected repository and then shows the draft, so
/// one preview exercises the real lookup. With `foods.sqlite` not yet built into the
/// bundle nothing matches and every row asks for a food, which is the honest state.
private struct ResolvedEstimatePreview: View {
    let estimate: MealEstimate

    @Environment(\.foodRepository) private var repository
    @State private var draft: EstimateDraft?

    var body: some View {
        NavigationStack {
            if let draft {
                EstimateDraftView(draft: draft, day: .now) { _ in }
            } else {
                ProgressView()
            }
        }
        .task {
            let result = EstimateConversion.convert(estimate)
            let items = await EstimateResolver(repository: repository).resolve(result.items)
            draft = EstimateDraft(note: result.note, items: items)
        }
    }
}

#Preview("Three items, all matched") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.matchedDraft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Nothing matched, Log disabled") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.unmatchedDraft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Resolved against the bundled database") {
    ResolvedEstimatePreview(estimate: PreviewEstimates.breakfast)
        .previewEnvironment(seed: .empty)
}

#Preview("From a photo") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.matchedDraft, day: .now, photo: PreviewStore.samplePhoto) { _ in }
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Dark") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.matchedDraft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
    .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    NavigationStack {
        EstimateDraftView(draft: PreviewEstimates.matchedDraft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Invalid portion, Log disabled") {
    var draft = PreviewEstimates.matchedDraft
    draft.rows[1].gramsText = ""
    return NavigationStack {
        EstimateDraftView(draft: draft, day: .now) { _ in }
    }
    .previewEnvironment(seed: .empty)
}
#endif
