import SwiftUI

/// Onboarding gate, then the three tabs. Reconciliation itself starts in `AppServices`
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

/// Today, Library, Settings. Add and Quantity are sheets over Today, not tabs.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "calendar") {
                TodayView()
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
