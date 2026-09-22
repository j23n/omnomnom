import Foundation
import os
import SwiftUI
import UIKit

/// Per-nutrient write authorization. iOS never reports read status, so none is shown.
struct HealthStatusView: View {
    @Environment(\.health) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = HealthAuthorization.unavailable
    @State private var isRequesting = false

    var body: some View {
        List {
            Section {
                Text(authorization.summary)
            } footer: {
                Text("Health only tells apps what they may write. Entries are kept locally either way.")
            }
            if authorization.isAvailable {
                Section("Writing to Health") {
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        HStack {
                            Text(nutrient.displayName)
                            Spacer()
                            Text(authorization.writeStatusText(for: nutrient))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Button("Ask for Health access") {
                        Task { await request() }
                    }
                    .disabled(isRequesting)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open app settings", destination: url)
                    }
                } footer: {
                    Text("Health shows the sheet once per nutrient. Permissions live in Health › Sharing › Apps.")
                }
            }
        }
        .navigationTitle("Health")
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        authorization = await HealthAuthorization.current(from: health)
    }

    private func request() async {
        isRequesting = true
        do {
            try await health.requestAuthorization()
        } catch {
            AppLog.health.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
        isRequesting = false
    }
}

#if DEBUG
#Preview("All authorized") {
    NavigationStack {
        HealthStatusView()
    }
    .previewEnvironment(seed: .empty, health: .quiet)
}

#Preview("Partial authorization") {
    NavigationStack {
        HealthStatusView()
    }
    .previewEnvironment(seed: .empty, health: .partial)
}

#Preview("Nothing authorized") {
    NavigationStack {
        HealthStatusView()
    }
    .previewEnvironment(seed: .empty, health: .denied)
}

#Preview("Health unavailable") {
    NavigationStack {
        HealthStatusView()
    }
    .previewEnvironment(seed: .empty, health: .unavailable)
}
#endif
