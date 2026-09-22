import Foundation
import os
import SwiftUI

/// Two pages: what the app does, then the permission primer that precedes the
/// one-time Health sheet. Finishing marks onboarding complete whatever the outcome.
struct OnboardingView: View {
    @AppStorage(AppServices.onboardingKey) private var onboardingComplete = false
    @Environment(\.health) private var health
    @Environment(\.appServices) private var services
    @State private var page = 0
    @State private var isRequesting = false

    var body: some View {
        TabView(selection: $page) {
            IntroPage {
                withAnimation { page = 1 }
            }
            .tag(0)
            PermissionPrimerView(isHealthAvailable: health.isAvailable, isRequesting: isRequesting) {
                Task { await finish() }
            }
            .tag(1)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func finish() async {
        isRequesting = true
        do {
            try await health.requestAuthorization()
        } catch {
            AppLog.health.error("onboarding authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        isRequesting = false
        onboardingComplete = true
        services.startReconciliationIfNeeded()
    }
}

/// The mark and wordmark over the one paragraph that says what the app is. The copy
/// scrolls once the type size outgrows the page, so the Continue button stays put at
/// the bottom; at smaller sizes the scroll view centres it and does not bounce.
private struct IntroPage: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ScrollView {
                VStack(spacing: 24) {
                    BiteMark()
                        .fill(.tint)
                        .frame(width: 96, height: 96)
                    Wordmark()
                    Text("Log what you eat")
                        .font(.largeTitle.bold())
                    Text("Omnomnom is an entry mask for Apple Health. Search a food, type the amount, and the nutrients go to Health. No scores, no advice, no account, and it works offline.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
            Button {
                next()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
    }
}

#if DEBUG
#Preview("Page 1") {
    OnboardingView()
        .previewEnvironment(seed: .empty, defaults: PreviewDefaults.onboardingPending)
}

#Preview("Page 1, Health unavailable, dark") {
    OnboardingView()
        .previewEnvironment(seed: .empty, health: .unavailable, defaults: PreviewDefaults.onboardingPending)
        .preferredColorScheme(.dark)
}

#Preview("Page 1, accessibility 5") {
    OnboardingView()
        .previewEnvironment(seed: .empty, defaults: PreviewDefaults.onboardingPending)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
