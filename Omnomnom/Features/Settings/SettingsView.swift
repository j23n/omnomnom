import SwiftUI

/// Health status, the opt-in modules, and data sources.
struct SettingsView: View {
    @AppStorage(BarcodeModule.enabledKey) private var barcodeScanningEnabled = false
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
                Section {
                    Toggle("Barcode scanning", isOn: $barcodeScanningEnabled)
                } header: {
                    Text("Modules")
                } footer: {
                    Text("Scans run on this device. Looking up a product sends its barcode to Open Food Facts; results are kept on this device.")
                }
                Section {
                    Text("Photo estimation arrives in a later version.")
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
