import Foundation
import SwiftData
import SwiftUI

/// The selected day's totals and entries. The day is the title, and day navigation and
/// the Add button live in the toolbar.
///
/// The field is not here. It is over the tab bar, where every tab has it, and this screen's
/// only part in that is telling it which day a line goes into — Today holds the app's one
/// day selector. What is left at the bottom is this screen's own notices.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(\.foodRepository) private var repository
    @Environment(\.health) private var health
    /// The one field, which lives over the tab bar rather than on this screen. Today has
    /// the only day selector in the app, so it is what tells the field which day a line
    /// goes into.
    @Environment(\.composer) private var composer
    /// The validator runs on the same model the estimate module uses, behind the same
    /// opt-in, so a user who has not turned that on is not quietly handed a model call.
    @AppStorage(EstimationModule.enabledKey) private var estimationEnabled = false
    /// The opt-in that already governs searching Open Food Facts by name, read here because
    /// the fourth rung is that same search asked by the resolver rather than by the user.
    @AppStorage(BarcodeModule.productSearchKey) private var productSearchEnabled = false
    @State private var model: TodayViewModel

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
                // Only this screen's own notices. The field itself is over the tab bar,
                // where every tab has it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    TodayBottomBar(model: model)
                }
                // Dragging the day away puts the keyboard down, which is the gesture
                // people try first.
                .scrollDismissesKeyboard(.interactively)
                // The field logs into the day being looked at, and this is the only screen
                // where that is not today.
                .onAppear { composer.looking(at: model.selectedDay) }
                .onChange(of: model.selectedDay) { _, day in
                    composer.looking(at: day)
                }
                .onOpenURL { url in
                    guard let id = WidgetSnapshot.phraseID(from: url) else { return }
                    Task { await logFromWidget(id) }
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

    /// The four rungs, as the app wires them. Only the widget path needs them here; the
    /// field over the tab bar builds its own from the same factory.
    private var resolver: LineResolver {
        LineResolver.app(
            context: context,
            repository: repository,
            estimationEnabled: estimationEnabled,
            productSearchEnabled: productSearchEnabled
        )
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
        composer.show(logged: LoggedLine(resolution: resolution, outcome: outcome))
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
