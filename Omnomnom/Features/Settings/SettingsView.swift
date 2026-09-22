import SwiftUI

/// Health status, the opt-in modules with their state, data sources, and an About row
/// with the mark, the wordmark and the version.
struct SettingsView: View {
    @AppStorage(BarcodeModule.enabledKey) private var barcodeScanningEnabled = false
    @AppStorage(EstimationModule.enabledKey) private var mealEstimationEnabled = false
    @Environment(\.health) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = HealthAuthorization.unavailable
    @State private var estimation: EstimationAvailability?
    /// A fixed model state for previews; `nil` reads the model.
    private let fixedEstimation: EstimationAvailability?

    init(estimationAvailability: EstimationAvailability? = nil) {
        fixedEstimation = estimationAvailability
    }

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
                Section("About") {
                    HStack(alignment: .top, spacing: 12) {
                        BiteMark()
                            .fill(.tint)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Wordmark()
                            Text(AppVersion.display)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Your food log, written to Health.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Settings")
            .task(id: scenePhase) {
                estimation = fixedEstimation ?? EstimationAvailability.current()
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

#if DEBUG
#Preview("Health, all authorized") {
    SettingsView(estimationAvailability: .available(photo: false))
        .previewEnvironment(seed: .empty, health: .quiet)
}

#Preview("Health, partial authorization") {
    SettingsView(estimationAvailability: .available(photo: false))
        .previewEnvironment(seed: .empty, health: .partial)
}

#Preview("Health unavailable") {
    SettingsView(estimationAvailability: .deviceNotEligible)
        .previewEnvironment(seed: .empty, health: .unavailable)
}

#Preview("Modules on, model not ready") {
    SettingsView(estimationAvailability: .modelNotReady)
        .previewEnvironment(seed: .empty, health: .quiet, defaults: PreviewDefaults.modulesOn)
}

#Preview("Modules on, accessibility 5") {
    SettingsView(estimationAvailability: .appleIntelligenceNotEnabled)
        .previewEnvironment(seed: .empty, health: .quiet, defaults: PreviewDefaults.modulesOn)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Health, none authorized") {
    SettingsView(estimationAvailability: .available(photo: false))
        .previewEnvironment(seed: .empty, health: .denied)
}
#endif
