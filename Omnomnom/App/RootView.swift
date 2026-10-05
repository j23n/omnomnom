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
/// Everything the field leads to — the sign-off sheet, the Add screen, Quantity — is still
/// presented rather than pushed, so the input path stays one screen deep however many ways
/// into it there are.
struct MainTabView: View {
    /// Which tab is up, kept only so that leaving Today points the field back at today:
    /// Today is the one screen that can be showing another day, and a line typed anywhere
    /// else can only mean now.
    private enum Showing: Hashable {
        case today, shape, library, settings
    }

    @State private var composer = ComposerModel()
    @State private var showing: Showing = .today

    var body: some View {
        TabView(selection: $showing) {
            Tab("Today", systemImage: "calendar", value: Showing.today) {
                TodayView()
            }
            Tab("Shape", systemImage: "chart.xyaxis.line", value: Showing.shape) {
                ShapeView()
            }
            Tab("Library", systemImage: "books.vertical", value: Showing.library) {
                LibraryView()
            }
            Tab("Settings", systemImage: "gear", value: Showing.settings) {
                SettingsView()
            }
        }
        .onChange(of: showing) { _, tab in
            guard tab != .today else { return }
            composer.looking(at: .now)
        }
        // An inset and not a bar. A bar does not move for the keyboard, so the field it
        // holds ends up underneath one, which undoes the whole point of the field being
        // in reach of a thumb. An inset is laid out above the keyboard as any other
        // content would be.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerBar()
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
