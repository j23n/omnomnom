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
                    TodayBottomBar(
                        model: model,
                        composer: composer,
                        onSubmit: send,
                        onUndo: undo
                    )
                }
                // Dragging the day away puts the keyboard down, which is the gesture
                // people try first.
                .scrollDismissesKeyboard(.interactively)
                // Pushed, not presented. Naming a food means searching for one and
                // choosing a weight, and both of those want a screen of their own on top
                // of this one — which a sheet cannot give them, because the thing it would
                // have to present belongs to whatever put the sheet up.
                //
                // Only ever up for the rows a send could not place, and only when the user
                // asks. A line that resolved cleanly is in the day already.
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
                            composer.clearUnplaced()
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
                    // the user lands on what became of it rather than on an empty field.
                    guard let line else { return }
                    composer.line = line
                    router.clearPendingLine()
                    send()
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
            products: productLookup,
            estimator: Estimators.current()
        )
    }

    /// The fourth rung, and `nil` when the user has not turned product search on — which is
    /// not the same as a rung that answers nothing: `nil` means nothing may be asked at all,
    /// so an unmatched food goes straight to the user as it did before this existed.
    ///
    /// Its own property rather than a ternary inside the resolver, so the closure's type is
    /// stated where it is written instead of inferred through a conditional.
    private var productLookup: ((String) async -> [FoodChoice])? {
        guard productSearchEnabled else { return nil }
        return { await ProductRung.choices(for: $0, in: context) }
    }

    /// Sends what is in the field: resolves it, and logs what came back.
    ///
    /// The meal and the time are nobody's decision here. The model's reading of which meal
    /// this is wins, since oats at nine in the evening are breakfast, and the clock decides
    /// when nothing read it — the same rule the sign-off screen used to default to, applied
    /// without asking. Both are still changeable afterwards, on the entry itself.
    private func send() {
        let day = model.selectedDay
        composer.submit(using: resolver) { placed in
            let slot = placed.meal ?? MealSlot.inferred(from: QuantitySheet.defaultTimestamp(on: day))
            await log(placed, mealSlot: slot, at: slot.timestamp(on: day))
        }
    }

    /// Takes back what the last line wrote.
    private func undo() {
        guard let logged = model.lastLogged else { return }
        Task { await model.undo(logged, using: EntryLogger(context: context, health: health)) }
    }

    /// Logs every row and offers the way back from it.
    ///
    /// Nothing is signed off first. What the line said, with a food behind it and no
    /// question over it, is in the day by the time the user has looked up from the field,
    /// and `LoggedLine` is what makes that safe rather than merely fast.
    private func log(_ resolution: LineResolution, mealSlot: MealSlot, at timestamp: Date) async {
        let logger = EntryLogger(context: context, health: health)
        let outcome = await logger.logLine(
            resolution,
            mealSlot: mealSlot,
            at: timestamp
        )
        model.show(logged: LoggedLine(resolution: resolution, outcome: outcome))
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
        model.show(logged: LoggedLine(resolution: resolution, outcome: outcome))
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
