import Foundation
import Security

/// Which model answers the composer.
///
/// On-device first wherever it can: it costs nothing, works without a network and sends
/// nothing anywhere. The remote option exists because Apple Intelligence is absent on
/// older hardware, in some regions and whenever it is switched off, and because a larger
/// model is simply better at breaking a named dish into its parts.
nonisolated enum EstimationProvider: String, CaseIterable, Codable, Sendable {
    case onDevice
    case remote

    static let key = "estimationProvider"

    var displayName: String {
        switch self {
        case .onDevice: "On this iPhone"
        case .remote: "Your own endpoint"
        }
    }

    /// Said in Settings, where the choice is made.
    var detail: String {
        switch self {
        case .onDevice:
            "Apple Intelligence. Nothing leaves the device."
        case .remote:
            "An OpenAI-compatible endpoint you run or pay for. What you type is sent to it."
        }
    }
}

/// Where a remote endpoint lives and what it is allowed to see.
///
/// The address and the model name are ordinary preferences. The key is not: it goes to the
/// keychain, because `UserDefaults` is readable from a backup and a key is a credential.
///
/// `sendsPhotos` is its own switch rather than part of the opt-in. A sentence about lunch
/// and a photograph of a kitchen are not the same disclosure, and plenty of
/// OpenAI-compatible servers cannot read an image at all.
nonisolated struct RemoteEstimatorSettings: Hashable, Sendable {
    static let baseURLKey = "remoteEstimatorBaseURL"
    static let modelKey = "remoteEstimatorModel"
    static let sendsPhotosKey = "remoteEstimatorSendsPhotos"

    /// The endpoint's root, without a path: "https://api.openai.com/v1".
    var baseURL: String
    var model: String
    var sendsPhotos: Bool

    init(baseURL: String = "", model: String = "", sendsPhotos: Bool = false) {
        self.baseURL = baseURL
        self.model = model
        self.sendsPhotos = sendsPhotos
    }

    /// The chat-completions URL, or `nil` when the address is not usable.
    ///
    /// Tolerant about the trailing slash and about the caller having already typed the
    /// path, because both are what people paste.
    var completionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        if url.path.hasSuffix("/chat/completions") { return url }
        while url.path.hasSuffix("/") { url.deleteLastPathComponent() }
        url.append(path: "chat/completions")
        return url
    }

    /// Whether this is complete enough to try.
    var isUsable: Bool {
        completionsURL != nil && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The remote endpoint's API key, in the keychain.
///
/// One item, replaced wholesale. Nothing here throws: a key that cannot be read is the
/// same situation as no key at all, which the caller already has to handle, and a
/// keychain error is not something the user can act on.
nonisolated enum EstimationKeychain {
    private static let account = "remote-estimator-api-key"
    private static let service = "com.j23n.omnomnom.estimation"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Stores `key`, or removes the item when `key` is empty.
    static func store(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return remove() }
        guard let data = trimmed.data(using: .utf8) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        // This device only: a key pasted on an iPhone should not travel to a Mac in a
        // backup, and the alternative is a synchronised credential nobody asked to share.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Whether a key is stored, without handing it to a view that only wants to say so.
    static var hasKey: Bool { read() != nil }
}

/// Builds the estimator the user's settings ask for.
///
/// One place, because three screens need the answer and a second reading of these defaults
/// would be a second chance to disagree about which model is answering. `nil` means none
/// will: Apple Intelligence chosen and unavailable, or an endpoint chosen and not yet
/// configured. The caller says so rather than failing — search and the barcode scanner are
/// how the app is used when no model will answer.
nonisolated enum Estimators {
    @MainActor
    static func current(defaults: UserDefaults = .standard) -> (any MealEstimating)? {
        switch chosen(defaults: defaults) {
        case .onDevice:
            guard EstimationAvailability.current().isAvailable else { return nil }
            return FoundationMealEstimator()
        case .remote:
            let settings = remoteSettings(defaults: defaults)
            guard settings.isUsable else { return nil }
            return RemoteMealEstimator(settings: settings, key: EstimationKeychain.read())
        }
    }

    /// Defaults to the device. A first run has sent nothing anywhere and should not need a
    /// decision before it works.
    static func chosen(defaults: UserDefaults = .standard) -> EstimationProvider {
        guard let raw = defaults.string(forKey: EstimationProvider.key),
              let provider = EstimationProvider(rawValue: raw)
        else { return .onDevice }
        return provider
    }

    static func remoteSettings(defaults: UserDefaults = .standard) -> RemoteEstimatorSettings {
        RemoteEstimatorSettings(
            baseURL: defaults.string(forKey: RemoteEstimatorSettings.baseURLKey) ?? "",
            model: defaults.string(forKey: RemoteEstimatorSettings.modelKey) ?? "",
            sendsPhotos: defaults.bool(forKey: RemoteEstimatorSettings.sendsPhotosKey)
        )
    }
}
