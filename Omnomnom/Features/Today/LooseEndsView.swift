import DeveloperToolsSupport
import Foundation
import SwiftData
import SwiftUI

/// Everything left to answer about a day, one card at a time.
///
/// It exists only when something is incomplete, and what it must never become is a chore
/// list. Nothing on it is a percentage and nothing fills a bar: a count goes down, the
/// mark's ring closes, and the run holds. Every card's second answer costs nothing —
/// "nothing tonight" closes a meal without inventing food, "it is right" closes a question
/// about a match without changing anything — because a queue where every exit writes
/// something is a queue that teaches people to invent food.
struct LooseEndsView: View {
    let day: Date
    /// The title the day goes by, for the line under the heading.
    let dayTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.foodRepository) private var repository
    @Environment(\.composer) private var composer
    @Query private var entries: [LogEntry]
    @Query private var dayRecords: [DayRecord]
    @Query private var baselines: [BaselinePhrase]
    @AppStorage(SamplingCadence.key) private var cadenceRaw = SamplingCadence.standard.rawValue
    /// The slot whose usual meal is being logged, so only that card shows a spinner.
    @State private var acceptingSlot: MealSlot?
    /// Figures the user has said to leave, for this visit only.
    ///
    /// Not stored, deliberately: a dismissal that outlived the day would be a standing
    /// instruction never to mention a nutrient again, which is not what "leave it" means.
    /// It means "not now", and the queue is per day anyway.
    @State private var left: Set<Nutrient> = []
    /// The marked row being asked about, if any.
    @State private var questioned: LogEntry?

    init(day: Date, dayTitle: String, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day)
        self.dayTitle = dayTitle
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<LogEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \LogEntry.timestamp
        )
        _dayRecords = Query(filter: #Predicate<DayRecord> { $0.day >= start && $0.day < end })
    }

    private var cadence: SamplingCadence {
        SamplingCadence(rawValue: cadenceRaw) ?? .standard
    }

    private var items: [LooseEnd] {
        LooseEnd.items(
            entries: entries,
            record: dayRecords.first,
            baselines: baselines,
            day: day,
            cadence: cadence
        )
        .filter { item in
            if case .missingFigure(let nutrient) = item.kind { return !left.contains(nutrient) }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LooseEnd.heading(items.count))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text(LooseEnd.subheading(items.count, day: dayTitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(items) { item in
                    Section {
                        card(item)
                    }
                }
            }
            .navigationTitle("Loose ends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Driven by the entry rather than by `sheet(item:)`, which would ask a
            // SwiftData model to be `Identifiable` across a delete — and answering a
            // question here can delete the row it is about.
            .sheet(isPresented: isQuestionPresented) {
                if let entry = questioned {
                    GuessedMatchSheet(
                        entry: entry,
                        load: { await candidates(for: entry) },
                        onSettle: { settle(entry.id) },
                        onReplace: { choice in Task { await replace(entry, with: choice) } }
                    )
                }
            }
        }
    }

    @ViewBuilder private func card(_ item: LooseEnd) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            choices(for: item)
        }
        .padding(.vertical, 4)
    }

    /// The two answers, the second of which always costs nothing.
    @ViewBuilder private func choices(for item: LooseEnd) -> some View {
        switch item.kind {
        case .unansweredMeal(let slot):
            HStack(spacing: 16) {
                if let phrase = offerable(slot) {
                    Button("Log the usual") {
                        Task { await accept(phrase, for: slot) }
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(acceptingSlot != nil)
                    if acceptingSlot == slot {
                        ProgressView().controlSize(.small)
                    }
                }
                Button("Nothing \(Self.when(slot))") { skip(slot) }
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .guessedMatch:
            HStack(spacing: 16) {
                Button("Choose the food") { questioned = entry(item.entryID) }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                Button("It is right") { settle(item.entryID) }
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .missingFigure(let nutrient):
            HStack(spacing: 16) {
                if let entry = entry(item.entryID) {
                    Button("Pick a fuller row") { questioned = entry }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                }
                Button("Leave it") { left.insert(nutrient) }
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .dayNotClosed:
            Button("Close the day") { close() }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .font(.subheadline)
        }
    }

    /// "Nothing this morning", "nothing tonight": the second answer in the words of the
    /// meal it answers, because "nothing for dinner" is not a sentence anyone says.
    static func when(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "this morning"
        case .lunch: "at lunch"
        case .dinner: "tonight"
        case .snack: "in between"
        }
    }

    private var isQuestionPresented: Binding<Bool> {
        Binding(
            get: { questioned != nil },
            set: { if !$0 { questioned = nil } }
        )
    }

    /// The foods a marked row's own words could have meant; the same search the guess came
    /// from, asked again now.
    private func candidates(for entry: LogEntry) async -> [FoodChoice] {
        guard let wording = entry.wording, !wording.isEmpty else { return [] }
        return await LineResolver(context: context, repository: repository).candidates(for: wording)
    }

    private func offerable(_ slot: MealSlot) -> Phrase? {
        guard let baseline = baselines.first(where: { $0.mealSlot == slot }), baseline.isOfferable
        else { return nil }
        return baseline.phrase
    }

    private func entry(_ id: UUID?) -> LogEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    private func accept(_ phrase: Phrase, for slot: MealSlot) async {
        acceptingSlot = slot
        defer { acceptingSlot = nil }
        let logger = EntryLogger(context: context, health: health)
        switch await logger.logUsual(
            phrase, for: slot, on: day,
            resolver: LineResolver(context: context, repository: repository)
        ) {
        case .logged(let line):
            composer.show(logged: line)
        case .gone:
            composer.banner = UsualOutcome.gone.message
        }
    }

    /// Answers a meal with nothing, which is what closes a day nobody ate four meals in.
    private func skip(_ slot: MealSlot) {
        do {
            try DayRecord.setSkipped(true, slot: slot, for: day, in: context)
            try context.save()
        } catch {
            AppLog.store.error("could not answer a meal: \(error.localizedDescription, privacy: .public)")
            composer.banner = "That meal could not be answered."
        }
    }

    private func settle(_ id: UUID?) {
        guard let entry = entry(id) else { return }
        EntryLogger(context: context, health: health).settle(entry)
    }

    private func close() {
        do {
            try DayRecord.setComplete(true, for: day, in: context)
            try context.save()
        } catch {
            AppLog.store.error("could not close the day: \(error.localizedDescription, privacy: .public)")
            composer.banner = "That day could not be marked."
        }
    }

    private func replace(_ entry: LogEntry, with choice: FoodChoice) async {
        let message = await EntryLogger(context: context, health: health)
            .replaceFood(of: entry, with: choice)
        composer.banner = message
    }
}

/// The row on Today that leads to the queue, shown only when there is something in it.
struct LooseEndsRow: View {
    let count: Int

    var body: some View {
        LabeledContent {
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            Text("Loose ends")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LooseEnd.heading(count))
    }
}

#if DEBUG
/// The queue over whichever day a seed holds, with the entries it holds marked up so the
/// cards have something to be about.
private struct LooseEndsPreview: View {
    let container: ModelContainer
    /// What to do to the seeded rows before the queue reads them.
    var prepare: ([LogEntry]) -> Void = { _ in }

    var body: some View {
        let entries = PreviewStore.entries(in: container)
        prepare(entries)
        return LooseEndsView(day: .now, dayTitle: "Today")
            .modelContainer(container)
            .environment(\.foodRepository, PreviewRepository.make())
    }
}

#Preview("Three loose ends") {
    LooseEndsPreview(container: PreviewStore.container(seed: .typicalDay)) { entries in
        if let first = entries.first {
            first.wording = "a side salad"
            first.guessed = true
        }
        // A row with no fibre figure, which is what 666 of the bundled rows look like.
        if entries.count > 1 {
            entries[1].snapshotFiber = nil
        }
    }
}

#Preview("A marked row and nothing else") {
    LooseEndsPreview(container: PreviewStore.container(seed: .typicalDay)) { entries in
        if let first = entries.first {
            first.wording = "oats"
            first.guessed = true
        }
    }
}

#Preview("Nothing loose") {
    LooseEndsPreview(container: PreviewStore.container(seed: .typicalDay))
}

#Preview("An empty day, every meal to answer") {
    LooseEndsPreview(container: PreviewStore.container(seed: .empty))
}

#Preview("Accessibility 5") {
    LooseEndsPreview(container: PreviewStore.container(seed: .typicalDay)) { entries in
        if let first = entries.first {
            first.wording = "a side salad"
            first.guessed = true
        }
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("The row", traits: .sizeThatFitsLayout) {
    List {
        LooseEndsRow(count: 3)
        LooseEndsRow(count: 1)
    }
}
#endif
