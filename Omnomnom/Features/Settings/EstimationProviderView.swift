import Foundation
import os
import SwiftUI

/// Which model answers the composer, and where that model lives.
///
/// This screen exists because of one failure: a composer that asks for an estimate and
/// gets nothing back, on a phone where Apple Intelligence is simply switched off, says
/// only that it could not. The honest answer is a sentence long and it belongs here, next
/// to the choice, so the availability message is shown whether or not it is bad news.
///
/// The remote option is the single place this app sends anything a user wrote. It is
/// therefore spelled out rather than summarised: what is sent, when, and to the address
/// they typed themselves. The copy states it and stops; nothing here is a warning, because
/// running your own endpoint is a reasonable thing to do and the user picked the host.
///
/// Deliberately left out: a button that tries the endpoint. A request from Settings would
/// need the prompt, the request shape and the error vocabulary that belong to the
/// estimator, and it would spend a user's tokens to tell them something the next meal they
/// log tells them for free. What this screen does instead is say whether the configuration
/// is complete enough to try, naming the part that is missing, so the only failure left is
/// a real one at the endpoint.
struct EstimationProviderView: View {
    @AppStorage(EstimationProvider.key) private var providerRaw = EstimationProvider.onDevice.rawValue
    @AppStorage(RemoteEstimatorSettings.baseURLKey) private var baseURL = ""
    @AppStorage(RemoteEstimatorSettings.modelKey) private var model = ""
    @AppStorage(RemoteEstimatorSettings.sendsPhotosKey) private var sendsPhotos = false
    @AppStorage(AnthropicSettings.baseURLKey) private var claudeBaseURL = ""
    @AppStorage(AnthropicSettings.modelKey) private var claudeModel = ""
    @AppStorage(AnthropicSettings.sendsPhotosKey) private var claudeSendsPhotos = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: EstimationAvailability?
    /// What is typed into the secure field, and nothing else. Never a key read back out of
    /// the keychain, and emptied the moment the key is written.
    @State private var keyEntry = ""
    @State private var hasStoredKey = false
    /// Fixed model state and key state for previews; `nil` reads the real ones.
    private let fixedAvailability: EstimationAvailability?
    private let fixedKeyStored: Bool?

    private var provider: EstimationProvider {
        EstimationProvider(rawValue: providerRaw) ?? .onDevice
    }

    private var remote: RemoteEstimatorSettings {
        RemoteEstimatorSettings(baseURL: baseURL, model: model, sendsPhotos: sendsPhotos)
    }

    /// What makes the availability and the stored key worth reading again: coming back to
    /// the screen, and changing which provider is selected, since the two keep separate
    /// keys. A string rather than a pair type, because that is all `task(id:)` wants.
    private var readingID: String {
        "\(provider.rawValue)-\(String(describing: scenePhase))"
    }

    private var claude: AnthropicSettings {
        AnthropicSettings(baseURL: claudeBaseURL, model: claudeModel, sendsPhotos: claudeSendsPhotos)
    }

    init(availability: EstimationAvailability? = nil, keyStored: Bool? = nil) {
        fixedAvailability = availability
        fixedKeyStored = keyStored
    }

    var body: some View {
        List {
            Section {
                Picker("Produced by", selection: $providerRaw) {
                    ForEach(EstimationProvider.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
            } footer: {
                Text(provider.detail)
            }
            switch provider {
            case .onDevice: onDeviceSection
            case .anthropic: claudeSections
            case .remote: remoteSections
            }
        }
        .navigationTitle("Estimates from")
        // Apple Intelligence is turned on in iOS Settings, a key can be removed from the
        // keychain by another screen, and the two providers keep separate keys — so the
        // question is asked again about whichever one is selected rather than once.
        .task(id: readingID) {
            availability = fixedAvailability ?? EstimationAvailability.current()
            hasStoredKey = fixedKeyStored ?? provider.keySlot.map(EstimationKeychain.hasKey) ?? false
        }
    }

    @ViewBuilder
    private var onDeviceSection: some View {
        if let availability {
            Section {
                Text(availability.message)
            } footer: {
                Text("Apple Intelligence runs the model on this iPhone. Nothing is sent anywhere and it works with no network at all.")
            }
        }
    }

    /// Claude, which is the one provider that searches this app's own database for itself.
    /// Both fields default, so the only thing this screen asks for is a key.
    @ViewBuilder
    private var claudeSections: some View {
        Section {
            TextField(AnthropicPayload.defaultModel, text: $claudeModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Model name")
        } header: {
            Text("Model")
        } footer: {
            Text(Self.claudeModelFooter)
        }
        Section {
            if hasStoredKey {
                LabeledContent("Key", value: "Stored")
                Button("Remove key", role: .destructive) { removeKey() }
            }
            SecureField(hasStoredKey ? "Replace the key" : "Key", text: $keyEntry)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { storeKey() }
            if !keyEntry.isEmpty {
                Button("Save key") { storeKey() }
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text(Self.keyFooter)
        }
        Section {
            Toggle("Send photos", isOn: $claudeSendsPhotos)
        } footer: {
            Text(Self.claudePhotoFooter)
        }
        Section {
            Text(claudeReadiness)
        } footer: {
            Text(Self.claudeDisclosure)
        }
    }

    /// Whether Claude is set up, and what is missing when it is not. The address is not
    /// asked for at all — it defaults — so a key is the only thing that can be absent.
    private var claudeReadiness: String {
        guard let url = claude.messagesURL else {
            return "That address cannot be used. Clear the field to use \(AnthropicPayload.defaultBaseURL)."
        }
        guard hasStoredKey else {
            return "Not set up yet. Add a key from your Anthropic account."
        }
        return "Ready. Lines are resolved by \(claude.resolved.model) at \(url.absoluteString)."
    }

    @ViewBuilder
    private var remoteSections: some View {
        Section {
            TextField("https://api.openai.com/v1", text: $baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel("Endpoint address")
            TextField("Model, such as gpt-4o-mini", text: $model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Model name")
        } header: {
            Text("Endpoint")
        } footer: {
            Text(Self.disclosure)
        }
        Section {
            if hasStoredKey {
                LabeledContent("Key", value: "Stored")
                Button("Remove key", role: .destructive) { removeKey() }
            }
            SecureField(hasStoredKey ? "Replace the key" : "Key", text: $keyEntry)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { storeKey() }
            if !keyEntry.isEmpty {
                Button("Save key") { storeKey() }
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text(Self.keyFooter)
        }
        Section {
            Toggle("Send photos", isOn: $sendsPhotos)
        } footer: {
            Text(Self.photoFooter)
        }
        Section {
            Text(readiness)
        }
    }

    /// Whether this is complete enough to try, and when it is not, which part is missing.
    ///
    /// Said here rather than left to the composer: an address without a model fails at the
    /// moment a meal is logged, which is the worst moment to discover it, and "it didn't
    /// work" is indistinguishable from an endpoint that is down. The resolved URL is shown
    /// because the path is appended for you, and someone who pasted a full chat-completions
    /// address deserves to see that it was not doubled.
    private var readiness: String {
        guard let url = remote.completionsURL else {
            return baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Not set up yet. Enter the address of an OpenAI-compatible endpoint and the model to ask for."
                : "That address cannot be used. It needs to start with https:// — or http:// on your own network — and name a host."
        }
        guard remote.isUsable else {
            return "Almost. Add the name of the model to ask for."
        }
        if hasStoredKey {
            return "Ready. Estimates are asked of \(url.absoluteString)."
        }
        return "Ready, with no key. Estimates are asked of \(url.absoluteString); a hosted endpoint will refuse them, one on your own network may not need a key at all."
    }

    /// Writes what was typed and clears it in the same breath, so the key lives in `@State`
    /// for as long as it takes to hand it to the keychain and no longer. An empty field is
    /// ignored rather than stored: `EstimationKeychain.store("")` removes the item, and
    /// tapping Save on an untouched field must not quietly delete a working key — that is
    /// what Remove key is for, where it is asked for plainly.
    private func storeKey() {
        let typed = keyEntry
        keyEntry = ""
        guard let slot = provider.keySlot,
              !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        EstimationKeychain.store(typed, in: slot)
        hasStoredKey = EstimationKeychain.hasKey(slot)
        // Never the key, not even its length: this log is read by whoever has the device.
        AppLog.estimation.info("remote estimator key stored")
    }

    private func removeKey() {
        guard let slot = provider.keySlot else { return }
        EstimationKeychain.remove(slot)
        keyEntry = ""
        hasStoredKey = false
        AppLog.estimation.info("remote estimator key removed")
    }

    /// The one disclosure in this app that cannot be shortened. Everything else it does is
    /// local, so this is the sentence that stops being true the moment a remote endpoint is
    /// chosen, and it says which text and which pictures go where.
    private static let disclosure = """
        An endpoint of your own is the one part of this app that sends what you write somewhere. \
        The meal you type on Today goes to the address above, with the model name and your key, \
        each time an estimate is asked for — and the photo too, while Send photos is on.

        Nothing else travels: your log, the food database and Health stay on this device. \
        Where the address points and what is kept there is between you and whoever runs it.
        """

    private static let keyFooter = """
        The key is kept in the keychain rather than with the other settings, because \
        settings are readable from a backup. This screen never shows it back, so there is \
        nothing here to read off an unlocked phone: type a new one to replace it, or remove \
        it to stop sending one.
        """

    /// Claude's own disclosure. It differs from the endpoint's in one way that is worth a
    /// sentence of its own: this provider reads the food database, so rows of it travel
    /// back as part of the conversation. They are the app's own reference data rather than
    /// anything about this person, and saying so is cheaper than letting someone discover
    /// that a request carries more than what they typed.
    private static let claudeDisclosure = """
        Claude is the one part of this app that sends what you write somewhere. The meal \
        you type on Today goes to Anthropic with your key, each time a line is resolved — \
        and the photo too, while Send photos is on.

        It also searches this app's food database for you, which is what makes it good at \
        this. The database stays on the device; what travels is the search terms it chooses \
        and the rows that came back, which are the app's own reference data and say nothing \
        about you. With product search on, those terms reach Open Food Facts as well.

        Nothing else travels: your log and Health stay on this device.
        """

    private static let claudeModelFooter = """
        Leave it empty for \(AnthropicPayload.defaultModel). A plain field rather than a \
        list, because model names move faster than this app ships — if your account has a \
        newer one, type it.
        """

    private static let claudePhotoFooter = """
        Off to begin with, and a separate choice from the text: a photo of a meal carries \
        whatever else was in the frame. A photo only arises when Meal estimation is on, \
        which is where the camera is.
        """

    private static let photoFooter = """
        Off to begin with, and a separate choice from the text: a photo of a meal carries \
        whatever else was in the frame, and many OpenAI-compatible servers cannot read an \
        image at all. A photo only arises when Meal estimation is on, which is where the \
        camera is.
        """
}

#if DEBUG
/// `@AppStorage` suites for the states this screen has, one suite per state so two
/// previews in the same canvas never share. The keychain is not available to a preview at
/// all, which is why the stored-key state is passed in rather than written.
private nonisolated enum EstimationProviderPreviewDefaults {
    static func make(
        provider: EstimationProvider, baseURL: String = "", model: String = "",
        sendsPhotos: Bool = false
    ) -> UserDefaults {
        let name = "com.j23n.omnomnom.preview.estimationProvider.\(provider.rawValue)"
            + ".url\(baseURL.isEmpty).model\(model.isEmpty).photos\(sendsPhotos)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.set(provider.rawValue, forKey: EstimationProvider.key)
        if provider == .anthropic {
            defaults.set(baseURL, forKey: AnthropicSettings.baseURLKey)
            defaults.set(model, forKey: AnthropicSettings.modelKey)
            defaults.set(sendsPhotos, forKey: AnthropicSettings.sendsPhotosKey)
        } else {
            defaults.set(baseURL, forKey: RemoteEstimatorSettings.baseURLKey)
            defaults.set(model, forKey: RemoteEstimatorSettings.modelKey)
            defaults.set(sendsPhotos, forKey: RemoteEstimatorSettings.sendsPhotosKey)
        }
        return defaults
    }
}

#Preview("On this iPhone") {
    NavigationStack {
        EstimationProviderView(availability: .available(photo: true), keyStored: false)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(provider: .onDevice))
}

#Preview("On this iPhone, Apple Intelligence off") {
    NavigationStack {
        EstimationProviderView(availability: .appleIntelligenceNotEnabled, keyStored: false)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(provider: .onDevice))
}

#Preview("Claude, needs a key") {
    NavigationStack {
        EstimationProviderView(availability: .deviceNotEligible, keyStored: false)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(provider: .anthropic))
}

#Preview("Claude, ready") {
    NavigationStack {
        EstimationProviderView(availability: .deviceNotEligible, keyStored: true)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(
        provider: .anthropic, model: "claude-opus-5-5", sendsPhotos: true
    ))
}

#Preview("Endpoint, incomplete") {
    NavigationStack {
        EstimationProviderView(availability: .deviceNotEligible, keyStored: false)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(
        provider: .remote, baseURL: "https://example.invalid/v1"
    ))
}

#Preview("Endpoint, ready") {
    NavigationStack {
        EstimationProviderView(availability: .deviceNotEligible, keyStored: true)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(
        provider: .remote, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
        sendsPhotos: true
    ))
}

#Preview("Endpoint, ready, accessibility 5") {
    NavigationStack {
        EstimationProviderView(availability: .deviceNotEligible, keyStored: true)
    }
    .defaultAppStorage(EstimationProviderPreviewDefaults.make(
        provider: .remote, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
        sendsPhotos: true
    ))
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
