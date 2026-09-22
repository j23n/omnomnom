import Foundation
import os
import SwiftData
import SwiftUI

/// Correcting one logged entry: the amount, the meal slot and the time, with the
/// nutrition it will freeze shown live. The amount scales the entry's own snapshot, so
/// an entry whose food was edited or deleted still corrects cleanly. Save mirrors the
/// whole entry to Health again; the Health section says where the entry stands and
/// offers to write it once more, and the entry can be deleted from here.
///
/// The amount field does not take focus on appear: the editor opens on a value that is
/// already right, and a keyboard would cover the meal and time rows the user came for.
struct EntryEditorView: View {
    let entry: LogEntry
    /// Writes the entry to Health again and says how it went, for the notice section.
    let onRestore: (LogEntry) async -> String
    /// Deletes the entry; Today runs it and shows the banner.
    let onDelete: (LogEntry) -> Void
    /// Banner text for a finished save, or `nil` when it went through silently.
    let onFinished: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.foodRepository) private var foodRepository

    @State private var amountText: String
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    @State private var chips: [AmountChip]
    @State private var isWorking = false
    /// What the last save or restore has to say; also the save error.
    @State private var notice: String?
    @State private var isConfirmingDelete = false
    @FocusState private var amountFocused: Bool

    /// How the amount scales; `nil` for an entry with nothing to scale.
    private let basis: EntryAmountBasis?
    /// The entry as a choice, built once because it carries the entry's photo.
    private let choice: FoodChoice?
    /// What the editor opened with, so Save can stay disabled until something moves.
    /// The amount is kept as the text the field was seeded with, not as the entry's
    /// stored value: the two differ whenever the stored amount has a second decimal,
    /// and comparing against the raw value would call a freshly opened editor changed.
    private let openedAmountText: String
    private let openedMealSlot: MealSlot
    private let openedTimestamp: Date
    /// The unit the disabled field carries for an entry there is nothing to scale;
    /// unused while there is a basis, which names the unit through its choice.
    private let loggedMeasure: FoodMeasure

    init(
        entry: LogEntry,
        onRestore: @escaping (LogEntry) async -> String,
        onDelete: @escaping (LogEntry) -> Void,
        onFinished: @escaping (String?) -> Void
    ) {
        self.entry = entry
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onFinished = onFinished
        let basis = EntryAmountBasis(entry: entry)
        self.basis = basis
        choice = basis?.choice
        // Without a basis the entry may still hold an amount, only one that cannot be
        // scaled: a recipe entry whose servings count went to zero still weighs what it
        // weighed. The disabled field shows it rather than reading empty.
        let logged = Self.loggedAmount(of: entry)
        loggedMeasure = logged.measure
        let initialAmountText = basis.map { Formatters.prefillText($0.amount) }
            ?? (logged.value > 0 ? Formatters.prefillText(logged.value) : "")
        openedAmountText = initialAmountText
        openedMealSlot = entry.mealSlot
        openedTimestamp = entry.timestamp
        _amountText = State(initialValue: initialAmountText)
        _mealSlot = State(initialValue: entry.mealSlot)
        _timestamp = State(initialValue: entry.timestamp)
        _chips = State(initialValue: basis?.isServings == true ? AmountChip.servings : [])
    }

    /// Servings for a recipe entry, else the unit the entry was logged in.
    private var unit: AmountUnit {
        guard let choice else { return .food(loggedMeasure) }
        return AmountUnit(choice: choice)
    }

    /// The entry's own amount and the unit to show it in: the one it says it was logged
    /// in, or, when that part is empty, whichever part it does hold. A recipe entry that
    /// mixes units shows its mass; the whole pair is under Raw amount either way.
    private static func loggedAmount(of entry: LogEntry) -> (value: Double, measure: FoodMeasure) {
        let raw = entry.rawAmount
        if raw.amount(in: entry.measure) > 0 { return (raw.amount(in: entry.measure), entry.measure) }
        if raw.millilitres > 0 { return (raw.millilitres, .volume) }
        return (raw.grams, .mass)
    }

    private var amount: Double? {
        unit.parse(amountText)
    }

    /// The amount the editor opened with, read back out of the text the field was
    /// seeded with, so an untouched field compares equal.
    private var openedAmount: Double? {
        unit.parse(openedAmountText)
    }

    /// The nutrition the entry would freeze; the entry's own while there is nothing to scale.
    private var preview: Nutrition {
        guard let basis else { return entry.snapshot }
        return basis.snapshot(for: amount ?? 0)
    }

    /// What the typed servings come to, mass and volume apart; only a recipe shows it.
    private var rawAmount: RawAmount {
        guard let basis else { return entry.rawAmount }
        return basis.rawAmount(for: amount ?? 0)
    }

    /// Whether the typed amount differs from the one the editor opened with. An
    /// unchanged amount is never written back, so the rounding the field applies to a
    /// stored value with a second decimal never reaches the entry.
    private var amountChanged: Bool {
        guard let openedAmount, let amount else { return false }
        return amount != openedAmount
    }

    private var hasChanges: Bool {
        mealSlot != openedMealSlot || timestamp != openedTimestamp || amountChanged
    }

    private var canSave: Bool {
        guard !isWorking, hasChanges else { return false }
        return basis == nil || amount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                nutritionSection
                Section {
                    Picker("Meal", selection: $mealSlot) {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Text(slot.displayName).tag(slot)
                        }
                    }
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
                healthSection
                Section {
                    Button("Delete entry", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                if let notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .disabled(!canSave)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .confirmationDialog(
                "Delete this entry?", isPresented: $isConfirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete entry", role: .destructive) {
                    onDelete(entry)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .task { await loadPortionChips() }
        }
    }

    /// The amount field, or a disabled one with a note for an entry there is nothing to scale.
    @ViewBuilder
    private var amountSection: some View {
        if let choice {
            AmountSection(choice: choice, chips: chips, text: $amountText, isFocused: $amountFocused)
        } else {
            Section {
                Text(entry.foodName)
                    .font(.headline)
                AmountField(text: $amountText, unit: unit, isFocused: $amountFocused)
                    .disabled(true)
            } footer: {
                Text("This entry has no amount to scale.")
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            NutritionPreview(nutrition: preview)
            if basis?.isServings == true {
                LabeledContent("Raw amount", value: rawAmount.wholeText)
            }
        } header: {
            Text("Nutrition")
        } footer: {
            OpenFoodFactsAttribution(attribution: choice?.attribution)
        }
    }

    private var healthSection: some View {
        Section {
            Text(Self.message(for: entry))
                .foregroundStyle(.secondary)
            if entry.healthState != .synced {
                Button(Self.writeTitle(for: entry.healthState)) {
                    Task { await restore() }
                }
                .disabled(isWorking)
            }
        } header: {
            Text("Health")
        }
    }

    /// "again" is only true of an entry Health once held; one that never got there is
    /// being written for the first time.
    private static func writeTitle(for state: HealthState) -> String {
        state == .unauthorized ? "Write to Health" : "Write to Health again"
    }

    /// Where the entry stands with Health, in a sentence. For the states the user can
    /// act on this names what Health dropped, as the Today dialog did before; for one
    /// that never reached Health it says so without guessing why, since an empty
    /// written set covers both a refused permission and a write that failed.
    static func message(for entry: LogEntry) -> String {
        switch entry.healthState {
        case .synced:
            return "Written to Health."
        case .unauthorized:
            return "Health never got this entry. Write it to Health now, or leave it here."
        case .orphaned:
            return "Removed here but still in Health."
        case .partial, .gone:
            let missing = entry.missingFromHealth
            let what: String
            if entry.healthState == .gone || missing.count == entry.written.count {
                what = "Health no longer has this entry."
            } else {
                what = "Health no longer has \(missing.map { $0.displayName.lowercased() }.formatted(.list(type: .and)))."
            }
            return "\(what) Write it to Health again, or delete the entry here."
        }
    }

    /// Portion chips of a bundled food, as the Quantity sheet loads them. The typed
    /// amount is never replaced: the editor opens on the amount the entry already has.
    private func loadPortionChips() async {
        guard basis?.isServings == false, let bundledID = entry.food?.bundledID else { return }
        do {
            let portions = try await foodRepository.portions(for: bundledID)
            chips = AmountChip.portions(portions)
        } catch {
            AppLog.foodDB.error("portions failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Writes the entry to Health again and says so in the notice section: a banner
    /// would go up on Today, behind this sheet. The editor stays open, so an amount or
    /// time the user is part way through typing survives.
    private func restore() async {
        guard !isWorking else { return }
        isWorking = true
        notice = await onRestore(entry)
        isWorking = false
    }

    private func save() async {
        guard canSave else { return }
        isWorking = true
        notice = nil
        let logger = EntryLogger(context: context, health: health)
        do {
            let result: LogResult
            if let basis, let amount, amountChanged {
                result = try await logger.update(entry, amount: amount, basis: basis, mealSlot: mealSlot, at: timestamp)
            } else {
                result = try await logger.update(entry, mealSlot: mealSlot, at: timestamp)
            }
            onFinished(result.bannerMessage)
            dismiss()
        } catch {
            AppLog.store.error("entry edit failed: \(error.localizedDescription, privacy: .public)")
            notice = "Could not save: \(error.localizedDescription)"
            isWorking = false
        }
    }
}

#if DEBUG
/// The editor around whichever entry a seed holds, so a preview stays honest when a
/// seed changes rather than trapping on a force-unwrap.
private struct EditorPreview: View {
    let container: ModelContainer
    let entry: LogEntry?

    var body: some View {
        Group {
            if let entry {
                EntryEditorView(
                    entry: entry,
                    onRestore: { entry in "Wrote \(entry.foodName) to Health." },
                    onDelete: { _ in },
                    onFinished: { _ in }
                )
            } else {
                Text("No entry in this seed")
            }
        }
        .previewEnvironment(container: container)
    }
}

#Preview("Gram entry") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first { $0.servings == nil && !$0.isEstimate }
    return EditorPreview(container: container, entry: entry)
}

#Preview("Recipe entry") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first { $0.servings != nil }
    return EditorPreview(container: container, entry: entry)
}

#Preview("Estimate") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first { $0.isEstimate }
    return EditorPreview(container: container, entry: entry)
}

#Preview("Needs Health attention") {
    let container = PreviewStore.container(seed: .healthStates)
    return EditorPreview(container: container, entry: PreviewStore.entry(in: container, state: .partial))
}

#Preview("Never reached Health") {
    let container = PreviewStore.container(seed: .healthStates)
    return EditorPreview(container: container, entry: PreviewStore.entry(in: container, state: .unauthorized))
}

#Preview("Accessibility 5") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first { $0.servings != nil }
    return EditorPreview(container: container, entry: entry)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
