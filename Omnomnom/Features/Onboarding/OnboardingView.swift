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

private struct IntroPage: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Log what you eat")
                .font(.largeTitle.bold())
            Text("Omnomnom is an entry mask for Apple Health. Search a food, type the grams, and the nutrients go to Health. No scores, no advice, no account, and it works offline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue", action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
