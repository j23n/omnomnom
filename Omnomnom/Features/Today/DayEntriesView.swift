import Foundation
import os
import SwiftData
import SwiftUI

/// The entries of one day, queried live, with totals on top and swipe actions per row.
/// Local rows render first; what Health holds for the day is read afterwards and
/// folded into the totals and the "Also in Health" section. The day before is queried
/// too, only to know whether an empty today can offer to copy it.
struct DayEntriesView: View {
    let model: TodayViewModel
    private let interval: DateInterval

    @Environment(\.modelContext) private var context
    @Environment(\.health) private var health
    @Environment(\.healthObserving) private var observing
    @Environment(\.foodRepository) private var repository
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

    init(day: Date, model: TodayViewModel, calendar: Calendar = .current) {
        self.model = model
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
                  let baseline = baselines.first(where: { $0.mealSlot == slot }),
                  baseline.isOfferable,
                  let phrase = baseline.phrase
            else { return nil }
            return (slot, phrase)
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

    /// The editor's presentation, driven by the model's entry rather than by
    /// `sheet(item:)`, which would ask a SwiftData model to be `Identifiable` across
    /// a delete. Clearing the entry closes the sheet and closing it clears the entry.
    private var isEditorPresented: Binding<Bool> {
        Binding(
            get: { model.editingEntry != nil },
            set: { if !$0 { model.editingEntry = nil } }
        )
    }

    var body: some View {
        List {
            Section {
                TotalsRow(totals: totals, foreign: healthSummary.hasForeign ? healthSummary.foreign : nil)
                DayCoverageRow(
                    state: dayState,
                    isAsked: cadence.asks(about: interval.start),
                    onToggle: toggleDayComplete
                )
            }
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
            if entries.isEmpty {
                Section {
                    EmptyDayView(
                        canCopyYesterday: model.isShowingToday && !previousDayEntries.isEmpty,
                        isCopying: isCopying,
                        copyYesterday: copyPreviousDay
                    )
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
                            onEdit: { model.edit($0) }
                        )
                    }
                }
            }
            if !healthSummary.meals.isEmpty {
                ForeignMealsSection(meals: healthSummary.meals)
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
    /// Logs a slot's usual line, marked as assumed.
    ///
    /// This is the only place an entry is written without anyone describing it, and it
    /// still takes a tap. `EntryOrigin.baseline` is what keeps the day distinguishable
    /// afterwards: it reads as assumed rather than complete, and any mean including it
    /// says so.
    func accept(_ phrase: Phrase, for slot: MealSlot) async {
        acceptingSlot = slot
        defer { acceptingSlot = nil }
        let resolver = LineResolver(context: context, repository: repository)
        guard let resolution = resolver.resolution(for: phrase) else {
            model.show(banner: "That meal can't be logged any more: one of its foods is gone.")
            return
        }
        let timestamp = QuantitySheet.defaultTimestamp(on: interval.start)
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(
            resolution, mealSlot: slot, at: timestamp, origin: .baseline
        )
        phrase.noteRecalled()
        model.show(banner: TodayView.loggedMessage(outcome, of: resolution.rows.count))
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
