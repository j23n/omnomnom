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

/// Plain-language explanation shown before the system Health sheet.
private struct PermissionPrimerView: View {
    let isHealthAvailable: Bool
    let isRequesting: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Writing to Health")
                .font(.largeTitle.bold())
            Text("Each entry is written to Health as one food with these nutrients:")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    Label(nutrient.displayName, systemImage: "checkmark")
                }
            }
            .font(.callout)
            Text("Health shows write permission only; if you decline, the app keeps a local log.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(isHealthAvailable ? "Connect Health" : "Continue without Health", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
                .frame(maxWidth: .infinity)
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

#Preview("Page 2, Health available") {
    PermissionPrimerView(isHealthAvailable: true, isRequesting: false) {}
}

#Preview("Page 2, requesting") {
    PermissionPrimerView(isHealthAvailable: true, isRequesting: true) {}
}

#Preview("Page 2, Health unavailable") {
    PermissionPrimerView(isHealthAvailable: false, isRequesting: false) {}
}

#Preview("Page 2, accessibility 5") {
    PermissionPrimerView(isHealthAvailable: true, isRequesting: false) {}
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
