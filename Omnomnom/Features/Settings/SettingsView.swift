import SwiftUI

/// Health status, the opt-in modules with their state, and data sources.
struct SettingsView: View {
    @AppStorage(BarcodeModule.enabledKey) private var barcodeScanningEnabled = false
    @AppStorage(EstimationModule.enabledKey) private var mealEstimationEnabled = false
    @Environment(\.health) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = HealthAuthorization.unavailable
    @State private var estimation: EstimationAvailability?

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
                    Toggle("Meal estimation", isOn: $mealEstimationEnabled)
                    if let estimation, !estimation.isAvailable {
                        Text(estimation.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Modules")
                } footer: {
                    Text(Self.modulesFooter)
                }
                Section("Data") {
                    NavigationLink("Sources") {
                        SourcesView()
                    }
                }
            }
            .navigationTitle("Settings")
            .task(id: scenePhase) {
                estimation = EstimationAvailability.current()
                authorization = await HealthAuthorization.current(from: health)
            }
        }
    }

    /// One paragraph per module; the toggle stays enabled when the model is unavailable
    /// so the choice is remembered for when it is.
    private static let modulesFooter = """
        Barcode scans run on this device. Looking up a product sends its barcode to Open Food Facts; results are kept on this device.

        Estimates are produced on this device by Apple Intelligence. Nothing is sent anywhere. They are rough and you confirm every value before it is logged.
        """
}
