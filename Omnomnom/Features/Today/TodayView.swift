import Foundation
import SwiftData
import SwiftUI

/// The selected day's totals and entries. The day is the title, day navigation lives in
/// the toolbar and the add button in a bar at the bottom, within reach of the thumb.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appRouter) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.foodRepository) private var repository
    @Environment(\.health) private var health
    /// The validator runs on the same model the estimate module uses, behind the same
    /// opt-in, so a user who has not turned that on is not quietly handed a model call.
    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false
    @State private var model: TodayViewModel
    @State private var composer = ComposerModel()
    /// A row of the resolution sheet whose food the user wants to change.
    @State private var picking: ResolvedRow?
    /// A food the system asked the app to open, handed to the search screen once.
    @State private var opening: FoodChoice?

    /// Starts from `model`; previews pass one with a banner or the unauthorized notice already up.
    init(model: TodayViewModel = TodayViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            DayEntriesView(day: model.selectedDay, model: model)
                .navigationTitle(model.dayTitle)
                .navigationSubtitle(model.daySubtitle)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            model.showPreviousDay()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Previous day")
                        Button {
                            model.showNextDay()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .accessibilityLabel("Next day")
                        if !model.isShowingToday {
                            Button("Today") { model.showToday() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.isDatePickerPresented = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel("Choose a day")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.isAddPresented = true
                        } label: {
                            Label("Add food", systemImage: "plus")
                        }
                    }
                }
                .safeAreaBar(edge: .bottom) {
                    TodayBottomBar(model: model, composer: composer) {
                        composer.submit(using: resolver)
                    }
                }
                .sheet(item: $composer.resolution) { resolution in
                    ResolutionSheet(
                        resolution: resolution,
                        onChange: { composer.update($0) },
                        onRemove: { composer.remove($0) },
                        onPick: { picking = $0 },
                        onLog: { Task { await log(resolution) } }
                    )
                    .presentationDetents([.medium, .large])
                }
                .fullScreenCover(item: $picking) { row in
                    FoodSearchView(mode: .pick(multiple: false, onPick: { choose($0, for: row) }))
                }
                .onOpenURL { url in
                    guard let id = WidgetSnapshot.phraseID(from: url) else { return }
                    Task { await logFromWidget(id) }
                }
                .onChange(of: router.pendingLine) { _, line in
                    // Siri took a line it could not finish. The composer picks it up so
                    // the user lands on the question rather than on an empty field.
                    guard let line else { return }
                    composer.line = line
                    router.clearPendingLine()
                    composer.submit(using: resolver)
                }
                .onChange(of: composer.banner) { _, banner in
                    guard let banner else { return }
                    model.show(banner: banner)
                    composer.dismissBanner()
                }
                .fullScreenCover(isPresented: $model.isAddPresented) {
                    FoodSearchView(
                        mode: .log(
                            day: model.selectedDay,
                            onLogged: { model.handle($0) },
                            onMessage: { model.show(banner: $0) }
                        ),
                        opening: opening
                    )
                }
                .onChange(of: router.pendingChoice) { _, choice in
                    // Visual intelligence opened the app on a food. The search screen
                    // already owns the Quantity sheet, so it is handed the food rather
                    // than Today growing a sheet of its own for it.
                    guard let choice else { return }
                    opening = choice
                    router.clearPendingChoice()
                    model.isAddPresented = true
                }
                .sheet(isPresented: $model.isDatePickerPresented) {
                    DayPicker(model: model)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.sceneBecameActive()
                    }
                }
        }
    }

    /// The four rungs, wired to this screen's environment.
    ///
    /// The validator is present only when the estimation opt-in is on, which is the same
    /// switch the photo tier uses. Without it the line still resolves from history and
    /// the bundled tables; fewer rows settle and the sheet says so.
    private var resolver: LineResolver {
        LineResolver(
            context: context,
            repository: repository,
            validator: estimationEnabled ? FoundationMatchValidator() : nil
        )
    }

    /// Logs every row, clears the field, and reports what happened in one banner.
    private func log(_ resolution: LineResolution) async {
        let logger = EntryLogger(context: context, health: health)
        // The same day-to-timestamp rule the Quantity sheet uses: the selected day at
        // the current time, so logging into the past keeps a sensible hour and the meal
        // slot it implies. One rule for this, not two.
        let timestamp = QuantitySheet.defaultTimestamp(on: model.selectedDay)
        let outcome = await logger.logLine(
            resolution,
            mealSlot: MealSlot.inferred(from: timestamp),
            at: timestamp
        )
        composer.clear()
        model.show(banner: Self.loggedMessage(outcome, of: resolution.rows.count))
    }

    /// Logs the line a widget tap named.
    ///
    /// Written without asking again, because the tap on the widget is the tap: the rule is
    /// that nothing reaches Health unless the user acted, not that they must act twice.
    /// The day is shown underneath it straight away, so what was written is visible rather
    /// than only reported.
    private func logFromWidget(_ id: UUID) async {
        model.showToday()
        guard let phrase = WidgetSnapshotWriter.phrase(id: id, in: context),
              let resolution = resolver.resolution(for: phrase)
        else {
            model.show(banner: "That line can't be logged any more.")
            return
        }
        let timestamp = Date.now
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(
            resolution,
            mealSlot: phrase.lastSlot ?? MealSlot.inferred(from: timestamp),
            at: timestamp
        )
        model.show(banner: Self.loggedMessage(outcome, of: resolution.rows.count))
    }

    /// Hands a picked food to the row that asked for it, keeping the amount the row
    /// already had: the user changed what the food is, not how much of it there was.
    private func choose(_ choice: FoodChoice, for row: ResolvedRow) {
        var updated = row
        updated.choice = choice
        updated.confidence = .settled
        updated.implausible = false
        if updated.amount == 0 {
            updated.amount = choice.lastAmount ?? 100
        }
        composer.update(updated)
        picking = nil
    }

    /// One sentence for the whole line, naming only what the user can act on.
    static func loggedMessage(_ outcome: LineLogOutcome, of rows: Int) -> String {
        if outcome.loggedCount == 0 {
            return "Nothing could be logged from that line."
        }
        let logged = outcome.loggedCount == 1 ? "Logged 1 item." : "Logged \(outcome.loggedCount) items."
        var problems = outcome.failed > 0 ? ["\(outcome.failed) could not be logged."] : []
        var seen: Set<String> = []
        for message in outcome.results.compactMap(\.bannerMessage) where seen.insert(message).inserted {
            problems.append(message)
        }
        return ([logged] + problems).joined(separator: " ")
    }
}

#if DEBUG
#Preview("Empty day") {
    TodayView()
        .previewEnvironment(seed: .empty)
}

#Preview("Empty day with yesterday") {
    TodayView()
        .previewEnvironment(seed: .yesterdayOnly)
}

#Preview("First run") {
    TodayView()
        .previewEnvironment(seed: .firstRun)
}

#Preview("Typical day") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Health states") {
    TodayView()
        .previewEnvironment(seed: .healthStates)
}

#Preview("With foreign samples") {
    TodayView()
        .previewEnvironment(seed: .typicalDay, health: PreviewHealth())
}

#Preview("Accessibility 5") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
        .preferredColorScheme(.dark)
}

#Preview("Banner") {
    let model = TodayViewModel()
    model.banner = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil).bannerMessage
    return TodayView(model: model)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Health accepting nothing") {
    // The notice comes up on its own, off the day's Health read, rather than being set
    // on the model as the preview below sets it.
    TodayView()
        .previewEnvironment(seed: .typicalDay, health: .denied)
}

#Preview("Unauthorized notice") {
    let model = TodayViewModel()
    model.showsUnauthorizedNotice = true
    return TodayView(model: model)
        .previewEnvironment(seed: .healthStates)
}

#Preview("Past day") {
    let model = TodayViewModel()
    model.selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    return TodayView(model: model)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Bottom bar with banner and notice") {
    let model = TodayViewModel()
    model.banner = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil).bannerMessage
    model.showsUnauthorizedNotice = true
    return TodayView(model: model)
        .previewEnvironment(seed: .healthStates)
}
#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 768)) {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
}

#endif
