import Foundation
import os
import SwiftData
import SwiftUI

/// The entries of one day, queried live, with totals on top and swipe actions per row.
/// Local rows render first; what Health holds for the day is read afterwards and
/// folded into the totals and the "Also in Health" section. The day before is queried
/// too, only to know whether an empty today can offer to copy it. What is only proposed
/// sits under everything that is recorded; see `proposalsSection`.
struct DayEntriesView: View {
    let model: TodayViewModel
    private let interval: DateInterval
    /// The calendar the day's bounds were taken with, kept so everything else about the
    /// day is read in the same one.
    private let calendar: Calendar

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.healthObserving) private var observing
    @Environment(\.foodRepository) private var repository
    /// The one field, for the offer to take back what accepting a usual meal just wrote.
    @Environment(\.composer) private var composer
    @Query private var entries: [LogEntry]
    @Query private var previousDayEntries: [LogEntry]
    /// The record for this day, if anything has been said about it. A day nobody has
    /// marked has no row, which is why this is a list rather than a value.
    @Query private var dayRecords: [DayRecord]
    @Query private var baselines: [BaselinePhrase]
    /// The slot whose proposal is being accepted, so only that row shows a spinner.
    @State private var acceptingSlot: MealSlot?
    @AppStorage(SamplingCadence.key) private var cadenceRaw = SamplingCadence.standard.rawValue

    /// How often the app asks about a day; see `SamplingCadence`.
    private var cadence: SamplingCadence {
        SamplingCadence(rawValue: cadenceRaw) ?? .standard
    }
    @State private var healthSummary = DayHealthSummary.empty
    @State private var isCopying = false
    /// The marked entry being asked about, if any.
    @State private var questioned: LogEntry?
    /// Whether the loose-ends queue is up.
    @State private var isShowingLooseEnds = false

    init(day: Date, model: TodayViewModel, calendar: Calendar = .current) {
        self.model = model
        self.calendar = calendar
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let previousStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        interval = DateInterval(start: start, end: end)
        _entries = Query(
            filter: #Predicate<LogEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \LogEntry.timestamp
        )
        _previousDayEntries = Query(
            filter: #Predicate<LogEntry> { $0.timestamp >= previousStart && $0.timestamp < start },
            sort: \LogEntry.timestamp
        )
        _dayRecords = Query(
            filter: #Predicate<DayRecord> { $0.day >= start && $0.day < end }
        )
    }

    /// Slots with a usual line and nothing logged in them yet, today only.
    ///
    /// Only today: proposing a meal for last Tuesday would be inventing history rather
    /// than saving anyone a keystroke.
    private var proposals: [(slot: MealSlot, phrase: Phrase)] {
        guard model.isShowingToday else { return [] }
        return MealSlot.allCases.compactMap { slot in
            guard !entries.contains(where: { $0.mealSlot == slot }),
                  let phrase = usualLine(for: slot)
            else { return nil }
            return (slot, phrase)
        }
    }

    /// The slot's usual line when there is one worth offering, whether or not the slot
    /// already holds something.
    ///
    /// Read by both the proposal and the line about a proposal that is gone, so the two
    /// can never disagree about whether the slot had a usual line in the first place.
    private func usualLine(for slot: MealSlot) -> Phrase? {
        guard let baseline = baselines.first(where: { $0.mealSlot == slot }), baseline.isOfferable
        else { return nil }
        return baseline.phrase
    }

    /// Whether this slot's proposal is gone because something else was logged into it.
    ///
    /// Logging into a slot removes that slot's proposal, and the removal is right: a card
    /// proposing lunch next to the lunch the user just typed would be offering to log a meal
    /// they already logged. But a card someone was looking at a second ago that is silently
    /// gone reads as the app losing it rather than as the app agreeing, which is the surprise
    /// the copy rule exists to prevent. So the disappearance gets a sentence, in the secondary
    /// ink, under the meal that caused it rather than next to the proposals that are left — it
    /// is about the meal, and that is where it will be read as an answer.
    ///
    /// What that sentence does not say is the point of it. No comparison with what the usual
    /// line would have come to, no remark that the meal was unusual, and no offer to update the
    /// baseline. The baseline follows the data; the data is never asked to follow the baseline.
    ///
    /// Four cases arrive at the same screen and exactly one of them deserves a word.
    ///
    /// A slot with no usual line, or one whose usual line was declined or can no longer be
    /// resolved, proposed nothing today: `usualLine` is `nil` and there is nothing to
    /// account for. A slot with nothing logged still has its proposal on screen. A slot
    /// holding entries of origin `.baseline` is one whose proposal was *accepted* — the
    /// card did not vanish, it became those rows, and saying anything about it would be
    /// claiming a deviation that did not happen. What is left is the slot that was typed
    /// into, where a card the user was looking at a second ago is simply not there.
    ///
    /// The last clause is what keeps this honest, and it is the one worth defending.
    /// Logging the usual line itself — typed by hand, repeated from yesterday, copied from
    /// the day before — also removes the proposal, and nothing was replaced: everything
    /// that line names is on the screen. An entry records no phrase, so the comparison is
    /// by the foods and recipes behind the rows rather than by wording, which is the right
    /// comparison anyway: what matters is whether the usual meal is there, not whether it
    /// was described the same way. It asks whether the usual line is *contained* in the
    /// slot and not whether it equals it, because a usual lunch plus a biscuit has not
    /// replaced anything either.
    ///
    /// It cannot tell a different amount of the same food from the usual amount of it, and
    /// deliberately does not try: half the usual porridge is still the usual porridge, and
    /// a line that appeared because someone weighed 40 g instead of 50 g would be noise.
    ///
    /// What it genuinely cannot tell is whether the card was ever on screen. Nothing
    /// records that a slot was proposed on a given day, so a lunch logged from the widget
    /// at noon and first looked at in the evening gets the line as well, for a card the
    /// user never saw. Said of the proposal it is still true — there is no proposal for
    /// lunch, and this entry is why — but it is one step closer to a remark about the meal
    /// than the design wants, and closing the gap needs a date on `BaselinePhrase` written
    /// when the row is shown rather than a cleverer reading of what is already stored.
    private func isDisplaced(_ slot: MealSlot) -> Bool {
        guard model.isShowingToday, let phrase = usualLine(for: slot) else { return false }
        let logged = entries.filter { $0.mealSlot == slot }
        guard !logged.isEmpty, !logged.contains(where: { $0.origin == .baseline }) else { return false }
        return !isCovered(phrase, by: logged)
    }

    /// Whether everything the usual line points at is among what is logged. A phrase with
    /// no items counts as uncovered, which cannot happen for an offerable baseline.
    private func isCovered(_ phrase: Phrase, by logged: [LogEntry]) -> Bool {
        let foods = Set(logged.compactMap { $0.food?.id })
        let recipes = Set(logged.compactMap { $0.recipe?.id })
        let items = phrase.orderedItems
        guard !items.isEmpty else { return false }
        return items.allSatisfy { item in
            if let food = item.food { return foods.contains(food.id) }
            if let recipe = item.recipe { return recipes.contains(recipe.id) }
            return false
        }
    }

    /// What kind of day this is, derived rather than stored; see `DayState`.
    private var dayState: DayState {
        DayState.derive(
            entryOrigins: entries.map(\.origin),
            markedComplete: dayRecords.first?.isComplete ?? false
        )
    }

    private var totals: Nutrition {
        SnapshotMath.total(of: entries.map(\.snapshot))
    }

    /// Which meals have an answer: the ones holding an entry, and the ones said to hold
    /// nothing. What the mark's ring draws.
    private var answers: DayAnswers {
        DayAnswers(
            entrySlots: entries.map(\.mealSlot),
            skipped: dayRecords.first?.skippedSlots ?? []
        )
    }

    /// The figures the mark and the bar are drawn from, which are the figures the totals
    /// show: what other sources wrote to Health for this day is part of the day, and a
    /// shape that left it out would disagree with the row underneath it.
    private var headlineNutrition: Nutrition {
        healthSummary.hasForeign ? totals + healthSummary.foreign : totals
    }

    private var composition: MacroComposition {
        MacroComposition(of: headlineNutrition)
    }

    /// Everything left to answer about this day. Read here only to count it; the queue
    /// itself reads the same thing from the same place.
    private var looseEnds: [LooseEnd] {
        LooseEnd.items(
            entries: entries,
            record: dayRecords.first,
            baselines: baselines,
            day: interval.start,
            cadence: cadence,
            calendar: calendar
        )
    }

    /// The editor's presentation, driven by the model's entry rather than by
    /// `sheet(item:)`, which would ask a SwiftData model to be `Identifiable` across
    /// a delete. Clearing the entry closes the sheet and closing it clears the entry.
    private var isEditorPresented: Binding<Bool> {
        Binding(
            get: { model.editingEntry != nil },
            set: { if !$0 { model.editingEntry = nil } }
        )
    }

    /// The same arrangement for the mark's question, and for the same reason: the entry it
    /// is about may be deleted by the answer.
    private var isQuestionPresented: Binding<Bool> {
        Binding(
            get: { questioned != nil },
            set: { if !$0 { questioned = nil } }
        )
    }

    /// The day's remaining proposals, placed twice in `body` rather than once.
    ///
    /// Once anything real is on the screen the proposal belongs under all of it, and the
    /// further the day fills the further it falls: on a list whose rows all look like
    /// records, the vertical order is the hierarchy a reader gets without being told one.
    /// An empty day has nothing for it to be under, and only one of the two placements is
    /// ever built, so the card is never on screen twice.
    @ViewBuilder private var proposalsSection: some View {
        if !proposals.isEmpty {
            Section {
                ForEach(proposals, id: \.slot) { proposal in
                    BaselineProposalRow(
                        slot: proposal.slot,
                        text: proposal.phrase.text,
                        isAccepting: acceptingSlot == proposal.slot,
                        onAccept: { Task { await accept(proposal.phrase, for: proposal.slot) } },
                        onDecline: { decline(proposal.slot) }
                    )
                }
            }
        }
    }

    /// The day as one mark and one sentence, with what is left to answer about it.
    ///
    /// Its own property so the queue is read once per redraw rather than once to ask
    /// whether it is empty and again to count it.
    @ViewBuilder private var headline: some View {
        let ends = looseEnds
        Section {
            DayHeadline(
                answers: answers,
                composition: composition,
                isAssumed: dayState == .assumed
            )
            // Only when there is something in it. A row saying nothing is loose is a row
            // about the app rather than about the day.
            if !ends.isEmpty {
                Button {
                    isShowingLooseEnds = true
                } label: {
                    LooseEndsRow(count: ends.count)
                }
            }
        }
    }

    var body: some View {
        List {
            headline
            if !composition.isEmpty {
                Section("What today was made of") {
                    CompositionBar(composition: composition)
                    CompositionLegend(composition: composition)
                }
            }
            Section {
                TotalsRow(totals: headlineNutrition, foreign: healthSummary.hasForeign ? healthSummary.foreign : nil)
                DayCoverageRow(
                    state: dayState,
                    isAsked: cadence.asks(about: interval.start),
                    onToggle: toggleDayComplete
                )
            }
            if entries.isEmpty {
                // Nothing real is on the screen yet, so the proposal has nothing to be
                // below and goes above the empty day's prompt: on a routine day it is the
                // cheaper of the two offers and should not be scrolled to.
                proposalsSection
                // The card for a day without entries, under the mark. On today, with
                // something logged yesterday it offers to copy those entries; any other
                // day only points at the Add button.
                Section {
                    ContentUnavailableView {
                        Label {
                            Text("Nothing logged")
                        } icon: {
                            BiteMark()
                                .fill(.tint)
                                .frame(width: 56, height: 56)
                        }
                    } description: {
                        Text("Use Add food below.")
                    } actions: {
                        if model.isShowingToday && !previousDayEntries.isEmpty {
                            Button("Copy yesterday", action: copyPreviousDay)
                                .buttonStyle(.bordered)
                                .disabled(isCopying)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    let slotEntries = entries.filter { $0.mealSlot == slot }
                    if !slotEntries.isEmpty {
                        MealSection(
                            slot: slot,
                            entries: slotEntries,
                            onDelete: delete,
                            onRepeat: repeatEntry,
                            onEdit: { model.edit($0) },
                            onQuestion: { questioned = $0 }
                        )
                        if isDisplaced(slot) {
                            // Directly under the meal that displaced it, with no card of
                            // its own, so it reads as a footnote to those rows rather
                            // than as another thing on the day.
                            Section {
                                Text("Replaced your usual \(slot.displayName.lowercased()).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .listSectionSpacing(.compact)
                        }
                    }
                }
            }
            if !healthSummary.meals.isEmpty {
                ForeignMealsSection(meals: healthSummary.meals)
            }
            if !entries.isEmpty {
                proposalsSection
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: isEditorPresented) {
            if let entry = model.editingEntry {
                EntryEditorView(entry: entry, onRestore: restore, onDelete: delete) { banner in
                    model.finishedEdit(banner: banner)
                }
            }
        }
        .sheet(isPresented: $isShowingLooseEnds) {
            LooseEndsView(day: interval.start, dayTitle: model.dayTitle, calendar: calendar)
        }
        .sheet(isPresented: isQuestionPresented) {
            if let entry = questioned {
                GuessedMatchSheet(
                    entry: entry,
                    load: { await candidates(for: entry) },
                    onSettle: { settle(entry) },
                    onReplace: { choice in Task { await replace(entry, with: choice) } }
                )
            }
        }
        .task(id: HealthReadKey(interval: interval, generation: model.healthRefresh)) {
            await readHealth()
        }
    }

    /// The one visit to Health per day shown. The day's samples come first, since they
    /// are what the screen is waiting on; the authorization behind the notice follows.
    /// Both are actor hops, so they run off the day's task rather than off anything a
    /// redraw evaluates.
    private func readHealth() async {
        await loadHealthSummary()
        let authorization = await HealthAuthorization.current(from: health)
        model.noteHealthAuthorization(authorization, hasEntries: !entries.isEmpty)
    }

    /// Reads the day from Health after the local rows are on screen; a failure leaves the
    /// previous summary in place and is logged inside the Health actor.
    private func loadHealthSummary() async {
        guard let samples = try? await observing.samples(in: interval) else { return }
        let summary = DayHealthSummary.make(from: samples, localEntryIDs: Set(entries.map(\.id)))
        healthSummary = summary
        AppLog.health.debug("day read: local \(totals.energy ?? 0) kcal, mirrored in Health \(summary.own.energy ?? 0) kcal, foreign \(summary.foreign.energy ?? 0) kcal")
    }

    private func delete(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.delete(entry, using: logger)
        }
    }

    /// Awaited by the editor, which shows the outcome in the sheet the user is looking at.
    private func restore(_ entry: LogEntry) async -> String {
        await model.restore(entry, using: EntryLogger(context: context, health: health))
    }

    private func repeatEntry(_ entry: LogEntry) {
        let logger = EntryLogger(context: context, health: health)
        Task {
            await model.repeatEntry(entry, using: logger)
        }
    }

    /// Re-logs yesterday's entries into today; the button stays disabled until the last
    /// one has been mirrored, so a second tap cannot double the day.
    private func copyPreviousDay() {
        guard !isCopying else { return }
        isCopying = true
        let logger = EntryLogger(context: context, health: health)
        let entries = previousDayEntries
        Task {
            await model.copyPreviousDay(entries, using: logger)
            isCopying = false
        }
    }
}

/// Identity of one Health read: the day window and a counter that forces a re-read.
private nonisolated struct HealthReadKey: Hashable, Sendable {
    let interval: DateInterval
    let generation: Int
}

#if DEBUG
/// Installs baselines on top of a seeded container. No `PreviewSeed` holds one, and this
/// screen is the only thing that reads them, so they are built here rather than threaded
/// through every seed.
///
/// Each pair names a slot and enough of a food's name to find it in the seed. A slot that
/// already holds entries of other foods therefore reads as displaced, an empty slot reads
/// as still proposed, and pointing a baseline at a food the slot already holds reads as
/// nothing having happened — the three states the screen has to keep apart.
@MainActor
private func seedBaselines(
    _ pairs: [(slot: MealSlot, food: String, line: String)], in container: ModelContainer
) {
    let context = container.mainContext
    let foods = PreviewStore.foods(in: container)
    for pair in pairs {
        guard let food = foods.first(where: { $0.name.localizedCaseInsensitiveContains(pair.food) })
        else { continue }
        let phrase = Phrase(key: pair.line, text: pair.line)
        context.insert(phrase)
        let item = PhraseItem(sortIndex: 0, name: food.name, amount: 100)
        context.insert(item)
        item.food = food
        item.phrase = phrase
        phrase.useCount = 4
        phrase.lastSlot = pair.slot
        let baseline = BaselinePhrase(mealSlot: pair.slot)
        context.insert(baseline)
        baseline.phrase = phrase
    }
    do {
        try context.save()
    } catch {
        AppLog.store.error("preview baselines failed: \(error.localizedDescription, privacy: .public)")
    }
}

#Preview("Typical day") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .typicalDay)
}

#Preview("Empty day") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Empty day with yesterday") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .yesterdayOnly)
}

#Preview("Health states") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .healthStates)
}

#Preview("With foreign samples") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .typicalDay, health: PreviewHealth())
}

#Preview("Accessibility 5, dark") {
    NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(seed: .typicalDay, health: PreviewHealth())
    .environment(\.dynamicTypeSize, .accessibility5)
    .preferredColorScheme(.dark)
}

/// A usual lunch of lentils against a logged lunch of chicken and rice: the proposal is
/// gone and the line under Lunch says so.
#Preview("A usual replaced") {
    let container = PreviewStore.container(seed: .typicalDay)
    seedBaselines([(slot: .lunch, food: "Lentils", line: "dal and rice")], in: container)
    return NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(container: container)
}

/// The deviation as the design draws it: one slot logged and its usual replaced, the
/// slots that are still untouched proposed below it.
#Preview("A usual replaced, the rest proposed") {
    let container = PreviewStore.container(seed: .library)
    seedBaselines(
        [
            (slot: .dinner, food: "Sourdough bread", line: "sourdough with cheese"),
            (slot: .breakfast, food: "Homemade granola", line: "granola and yogurt"),
            (slot: .snack, food: "Greek yogurt", line: "skyr"),
        ],
        in: container
    )
    return NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(container: container)
}

/// The case that must stay silent: the usual lunch was logged by hand rather than
/// accepted, so the proposal is gone and nothing was replaced. No line anywhere.
#Preview("A usual logged by hand") {
    let container = PreviewStore.container(seed: .typicalDay)
    seedBaselines([(slot: .lunch, food: "Chicken", line: "chicken and rice")], in: container)
    return NavigationStack {
        DayEntriesView(day: .now, model: TodayViewModel())
    }
    .previewEnvironment(container: container)
}
#endif

extension DayEntriesView {
    /// Marks the day as everything the user ate, or takes that back.
    ///
    /// The record is created on the first mark and kept afterwards, so a day that was
    /// marked and then unmarked is distinguishable from one nobody has looked at. That
    /// matters for sampling, which asks about specific days.
    func toggleDayComplete() {
        let wanted = dayState != .complete
        do {
            try DayRecord.setComplete(wanted, for: interval.start, in: context)
            try context.save()
        } catch {
            AppLog.store.error("could not mark the day: \(error.localizedDescription, privacy: .public)")
            model.show(banner: "That day could not be marked.")
        }
    }
}

extension DayEntriesView {
    /// The foods the entry's own words could have meant, for the mark's question.
    ///
    /// Asked again rather than kept: a shortlist stored on the entry would be the tables as
    /// they were on the day it was logged, and the one thing someone opening this wants is
    /// what the app would say now. Nothing is asked of a model — the user is reading the
    /// list themselves, which is what the validator exists to spare them, not to compete
    /// with.
    func candidates(for entry: LogEntry) async -> [FoodChoice] {
        guard let wording = entry.wording, !wording.isEmpty else { return [] }
        return await LineResolver(context: context, repository: repository).candidates(for: wording)
    }

    /// The match was right. Nothing reaches Health: the mark was never part of what was
    /// written there.
    func settle(_ entry: LogEntry) {
        EntryLogger(context: context, health: health).settle(entry)
    }

    /// The match was wrong, and this is the food that was meant.
    func replace(_ entry: LogEntry, with choice: FoodChoice) async {
        let logger = EntryLogger(context: context, health: health)
        let message = await logger.replaceFood(of: entry, with: choice)
        model.finishedEdit(banner: message)
    }

    /// Logs a slot's usual line, through the one path that does it.
    func accept(_ phrase: Phrase, for slot: MealSlot) async {
        acceptingSlot = slot
        defer { acceptingSlot = nil }
        let logger = EntryLogger(context: context, health: health)
        switch await logger.logUsual(
            phrase,
            for: slot,
            on: interval.start,
            resolver: LineResolver(context: context, repository: repository)
        ) {
        case .logged(let line):
            composer.show(logged: line)
        case .gone:
            model.show(banner: UsualOutcome.goneMessage)
        }
    }

    /// Turns a slot's proposal down. Permanent until the user asks for it again, because
    /// an offer that keeps coming back is nagging rather than helping.
    func decline(_ slot: MealSlot) {
        do {
            try BaselinePhrase.baseline(for: slot, in: context)?.declinedAt = .now
            try context.save()
        } catch {
            AppLog.store.error("could not decline a proposal: \(error.localizedDescription, privacy: .public)")
        }
    }
}
