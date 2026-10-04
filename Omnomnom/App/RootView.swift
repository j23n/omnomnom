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

/// Today, Trends, Library, Settings.
///
/// Four now. The composer, the Add sheet, the resolution sheet and Quantity are all over
/// Today rather than destinations of their own, so the input path stays one screen deep
/// however many ways into it there are.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "calendar") {
                TodayView()
            }
            Tab("Trends", systemImage: "chart.xyaxis.line") {
                TrendsView()
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
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
