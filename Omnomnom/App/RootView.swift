import SwiftUI

/// Onboarding gate, then the four tabs. Reconciliation itself starts in `AppServices`
/// at launch; this view only asks for a re-run whenever the scene comes to the foreground.
struct RootView: View {
    @AppStorage(AppServices.onboardingKey) private var onboardingComplete = false
    @Environment(\.appServices) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.sceneBecameActive()
            }
        }
    }
}

/// Today, Shape, Library, Settings — and the field, over all four of them.
///
/// The field is here rather than inside Today because logging a meal is not a place you go.
/// It was Today's alone, and Today is where you look at what you ate, which is a different
/// activity from saying what you ate and was in the way of it. One `ComposerModel` for the
/// whole app, so a line half typed survives a change of tab and an Undo stays reachable
/// from wherever the user went next.
///
/// The field itself is applied by each tab, with `composingTab`, rather than to the tab
/// view: an inset here would belong to the tab bar's chrome, where it drew over the bar,
/// took keystrokes meant for the field as tab selection, and re-laid-out the whole tab on
/// every character. What is shared is the state and not the placement.
///
/// Everything the field leads to — the sign-off sheet, the Add screen, Quantity — is still
/// presented rather than pushed, so the input path stays one screen deep however many ways
/// into it there are.
struct MainTabView: View {
    @State private var composer = ComposerModel()

    var body: some View {
        TabView {
            Tab("Today", systemImage: "calendar") {
                TodayView()
            }
            Tab("Shape", systemImage: "chart.xyaxis.line") {
                ShapeView()
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .environment(\.composer, composer)
    }
}

#if DEBUG
#Preview("Onboarding pending") {
    RootView()
        .previewEnvironment(seed: .empty, defaults: PreviewDefaults.onboardingPending)
}

#Preview("Main tabs") {
    RootView()
        .previewEnvironment(seed: .typicalDay)
}
#endif
