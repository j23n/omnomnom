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
    /// The opt-in that already governs searching Open Food Facts by name, read here because
    /// the fourth rung is that same search asked by the resolver rather than by the user.
    @AppStorage(BarcodeModule.productSearchKey) private var productSearchEnabled = false
    @State private var model: TodayViewModel
    @State private var composer = ComposerModel()

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
                // An inset and not a bar. A bar does not move for the keyboard, so the
                // field it holds ended up underneath one, which is the whole point of the
                // field being in reach of a thumb undone. An inset is laid out above the
                // keyboard as any other content would be.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TodayBottomBar(model: model, composer: composer) {
                        composer.submit(using: resolver)
                    }
                }
                // Dragging the day away puts the keyboard down, which is the gesture
                // people try first.
                .scrollDismissesKeyboard(.interactively)
                // Pushed, not presented. Signing off a meal means changing a food and
                // choosing a weight, and both of those want a screen of their own on top
                // of this one — which a sheet cannot give them, because the thing it would
                // have to present belongs to whatever put the sheet up.
                .navigationDestination(item: $composer.resolution) { resolution in
                    ResolutionScreen(
                        resolution: resolution,
                        day: model.selectedDay,
                        onChange: { composer.update($0) },
                        onRemove: { composer.remove($0) },
                        onAdd: { composer.add($0) },
                        onLog: { slot, at in
                            // The screen's own rows, not the resolution captured when it
                            // opened: an amount changed in it has to be the one logged.
                            let edited = composer.resolution ?? resolution
                            Task { await log(edited, mealSlot: slot, at: at) }
                        }
                    )
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
                        )
                    )
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
    /// The estimator is whichever model the user chose, and `nil` when none will answer —
    /// then only a line logged before comes back, and the composer says as much.
    ///
    /// The validator is separate and present only when the estimation opt-in is on. It is
    /// the second pass, the one that moves "oats" off an oat biscuit, and it is always the
    /// device's own model: a shortlist of candidate rows is a cheap question, and sending
    /// one somewhere would be a second disclosure for a smaller gain.
    private var resolver: LineResolver {
        LineResolver(
            context: context,
            repository: repository,
            validator: estimationEnabled ? FoundationMatchValidator() : nil,
            products: productSearchEnabled ? { await ProductRung.choices(for: $0, in: context) } : nil,
            estimator: Estimators.current()
        )
    }

    /// Logs every row, clears the field, and reports what happened in one banner.
    ///
    /// The meal and the time come from the sheet, which defaults them to the selected day
    /// at the current hour and then lets them be changed. They used to be inferred here,
    /// which meant a line could only ever be logged into the meal its hour implied.
    private func log(_ resolution: LineResolution, mealSlot: MealSlot, at timestamp: Date) async {
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(
            resolution,
            mealSlot: mealSlot,
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
