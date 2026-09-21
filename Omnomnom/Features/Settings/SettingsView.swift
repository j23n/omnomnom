import SwiftUI

/// Health status, the (not yet existing) opt-in modules, and data sources.
struct SettingsView: View {
    @Environment(\.health) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = HealthAuthorization.unavailable

    var body: some View {
        NavigationStack {
            List {
                Section("Health") {
                    NavigationLink {
                        HealthStatusView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health")
                            Text(authorization.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Optional features") {
                    Text("Barcode scanning and photo estimation arrive in a later version.")
                        .foregroundStyle(.secondary)
                }
                Section("Data") {
                    NavigationLink("Sources") {
                        SourcesView()
                    }
                }
            }
            .navigationTitle("Settings")
            .task(id: scenePhase) { authorization = await HealthAuthorization.current(from: health) }
        }
    }
}
