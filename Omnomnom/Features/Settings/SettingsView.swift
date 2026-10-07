import SwiftUI

/// Health status, the opt-in modules with their state, data sources, and an About row
/// with the mark, the wordmark and the version.
struct SettingsView: View {
    @AppStorage(BarcodeModule.enabledKey) private var barcodeScanningEnabled = false
    @AppStorage(BarcodeModule.productSearchKey) private var productSearchEnabled = false
    @AppStorage(EstimationModule.enabledKey) private var mealEstimationEnabled = false
    @AppStorage(EstimationProvider.key) private var providerRaw = EstimationProvider.onDevice.rawValue
    @AppStorage(SamplingCadence.key) private var cadenceRaw = SamplingCadence.standard.rawValue
    @Environment(\.health) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = HealthAuthorization.unavailable
    @State private var estimation: EstimationAvailability?
    /// A fixed model state for previews; `nil` reads the model.
    private let fixedEstimation: EstimationAvailability?

    private var cadence: SamplingCadence {
        SamplingCadence(rawValue: cadenceRaw) ?? .standard
    }

    private var provider: EstimationProvider {
        EstimationProvider(rawValue: providerRaw) ?? .onDevice
    }

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
                    Toggle("Product search", isOn: $productSearchEnabled)
                    Toggle("Meal estimation", isOn: $mealEstimationEnabled)
                    NavigationLink {
                        EstimationProviderView()
                    } label: {
                        LabeledContent("Estimates from", value: provider.displayName)
                    }
                    // Only about the on-device model, so it is not shown when something
                    // else is answering: a remote endpoint works on a device that has no
                    // Apple Intelligence at all, which is half the reason it exists.
                    if provider == .onDevice, let estimation, !estimation.isAvailable {
                        Text(estimation.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Modules")
                } footer: {
                    Text(modulesFooter)
                }
                Section {
                    NavigationLink("Headline figures") {
                        HeadlinePickerView()
                    }
                    Picker("Ask me about", selection: $cadenceRaw) {
                        ForEach(SamplingCadence.allCases) { cadence in
                            Text(cadence.label).tag(cadence.rawValue)
                        }
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text(cadence.explanation + " A day you mark complete always counts toward the trends, whether or not it was asked about.")
                }
                Section("Data") {
                    NavigationLink("Remembered lines") {
                        RememberedLinesView()
                    }
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
            .composingTab()
            .navigationTitle("Settings")
            .task(id: scenePhase) {
                estimation = fixedEstimation ?? EstimationAvailability.current()
                authorization = await HealthAuthorization.current(from: health)
            }
        }
    }

    /// One paragraph per module; the toggle stays enabled when the model is unavailable
    /// so the choice is remembered for when it is.
    ///
    /// The estimation paragraph follows the chosen provider. It used to promise that
    /// nothing is sent anywhere, which a remote endpoint makes untrue, and a sentence in
    /// Settings claiming a guarantee the app is no longer keeping is worse than no
    /// sentence at all.
    private var modulesFooter: String {
        """
        Barcode scans run on this device. Looking up a product sends its barcode to Open Food Facts; results are kept on this device.

        Product search sends what you type to Open Food Facts, so branded products can be found by name. The bundled database holds generic foods only and never a brand. With this on, a line you send is looked up there as well, food by food, and whichever answers better is what the sign-off screen shows.

        \(Self.estimationNote(for: provider))
        """
    }

    private static func estimationNote(for provider: EstimationProvider) -> String {
        switch provider {
        case .onDevice:
            "Estimates are produced on this device by Apple Intelligence. Nothing is sent anywhere. They are rough and you confirm every value before it is logged."
        case .remote:
            "Estimates are produced by the endpoint you entered, so the meal you type is sent to it. They are rough and you confirm every value before it is logged."
        }
    }
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
