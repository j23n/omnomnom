import Foundation
import Security

/// Which model is asked about a meal.
///
/// Reading what someone writes on Today means searching this app's database, which a model
/// does by calling a tool for it. Only the two remote options do, and that is a gap in this
/// app rather than a limit of the device: `FoundationModels` has had tool calling since
/// iOS 26 — a `Tool` with a name, a description, `@Generable` arguments and `call`, handed
/// to `LanguageModelSession(tools:)` — and iOS 27 adds a mode for governing when the model
/// may use one. Nobody has written the conformer, so on device answers the Add screen's
/// estimate and nothing on Today, neither a typed line nor a photo attached beside one.
/// `docs/OPEN-QUESTIONS.md` carries what it would take.
///
/// On-device still leads, because it costs nothing, works without a network and sends
/// nothing anywhere. The remote options exist because Apple Intelligence is absent on
/// older hardware, in some regions and whenever it is switched off, and because a larger
/// model is simply better at breaking a named dish into its parts.
/// Declaration order is the order Settings offers them, which is why Claude sits between
/// the two: it is the better answer for anyone the first option does not reach, and the
/// third is for an endpoint of one's own, which is a smaller audience with a clearer idea
/// of what they want.
nonisolated enum EstimationProvider: String, CaseIterable, Codable, Sendable {
    case onDevice
    case anthropic
    case remote

    static let key = "estimationProvider"

    var displayName: String {
        switch self {
        case .onDevice: "On this iPhone"
        case .anthropic: "Claude"
        case .remote: "Your own endpoint"
        }
    }

    /// Said in Settings, where the choice is made.
    var detail: String {
        switch self {
        case .onDevice:
            "Apple Intelligence, for the estimate on the Add screen. Nothing leaves the device. It does not yet read what you write on Today, which needs a model that searches the food database for you."
        case .anthropic:
            "Anthropic's API, with a key of yours. It searches this app's food database itself, and what you type is sent to it."
        case .remote:
            "An OpenAI-compatible endpoint you run or pay for. It searches this app's food database itself, and what you type is sent to it."
        }
    }

    /// Where this provider's key is kept. Separate items, so configuring one does not
    /// overwrite the other and switching back does not mean typing a key again.
    var keySlot: EstimationKeychain.Slot? {
        switch self {
        case .onDevice: nil
        case .anthropic: .anthropic
        case .remote: .openAICompatible
        }
    }
}

/// Where a provider's requests go: its base address with the API's path on the end.
///
/// One builder for both providers. Tolerant about a trailing slash and about the caller
/// having already typed the path, because both are what people paste, and strict about the
/// scheme, because anything else cannot be a request.
nonisolated enum EstimationEndpoint {
    static func url(base: String, path: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        if url.path.hasSuffix("/" + path) { return url }
        while url.path.hasSuffix("/") { url.deleteLastPathComponent() }
        url.append(path: path)
        return url
    }
}

/// Where Claude is asked, what model, and what it is allowed to see.
///
/// Its own type rather than `RemoteEstimatorSettings` with a different path appended. The
/// defaults differ, the path differs, and the two are configured independently — someone
/// trying both should not have the second overwrite the first.
nonisolated struct AnthropicSettings: Hashable, Sendable {
    static let baseURLKey = "anthropicBaseURL"
    static let modelKey = "anthropicModel"
    static let sendsPhotosKey = "anthropicSendsPhotos"

    /// The API root, without a path. Empty means the published one.
    var baseURL: String
    /// Empty means `AnthropicPayload.defaultModel`. A plain field rather than a picker:
    /// model names move faster than this app ships.
    var model: String
    var sendsPhotos: Bool

    init(baseURL: String = "", model: String = "", sendsPhotos: Bool = false) {
        self.baseURL = baseURL
        self.model = model
        self.sendsPhotos = sendsPhotos
    }

    /// What is actually asked for, with the two fields' defaults filled in, so one place
    /// decides what an empty field means and Settings can show the user the same answer.
    var resolved: AnthropicSettings {
        var copy = self
        if copy.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.baseURL = AnthropicPayload.defaultBaseURL
        }
        if copy.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.model = AnthropicPayload.defaultModel
        }
        return copy
    }

    /// The messages URL, or `nil` when the address is not usable.
    var messagesURL: URL? {
        EstimationEndpoint.url(base: resolved.baseURL, path: "messages")
    }

    /// Whether this is complete enough to try. Both fields default, so an address that
    /// parses is all it takes — the key is separate and a hosted API will say so itself.
    var isUsable: Bool {
        messagesURL != nil
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
    var completionsURL: URL? {
        EstimationEndpoint.url(base: baseURL, path: "chat/completions")
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
    private static let service = "com.j23n.omnomnom.estimation"

    /// Which provider's key. The raw value is the keychain account, and the first one keeps
    /// the name it had when there was only one remote provider, so a key already stored is
    /// still found rather than silently lost on update.
    nonisolated enum Slot: String, Hashable, Sendable, CaseIterable {
        case openAICompatible = "remote-estimator-api-key"
        case anthropic = "anthropic-api-key"
    }

    private static func baseQuery(_ slot: Slot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: slot.rawValue,
        ]
    }

    /// Stores `key`, or removes the item when `key` is empty.
    static func store(_ key: String, in slot: Slot) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return remove(slot) }
        guard let data = trimmed.data(using: .utf8) else { return }
        SecItemDelete(baseQuery(slot) as CFDictionary)
        var query = baseQuery(slot)
        query[kSecValueData as String] = data
        // This device only: a key pasted on an iPhone should not travel to a Mac in a
        // backup, and the alternative is a synchronised credential nobody asked to share.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ slot: Slot) -> String? {
        var query = baseQuery(slot)
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

    static func remove(_ slot: Slot) {
        SecItemDelete(baseQuery(slot) as CFDictionary)
    }

    /// Whether a key is stored, without handing it to a view that only wants to say so.
    static func hasKey(_ slot: Slot) -> Bool { read(slot) != nil }
}

/// Builds the model the user's settings ask for.
///
/// One place, because a second reading of these defaults would be a second chance to
/// disagree about which model is answering. `nil` means none will — a provider chosen and
/// not yet configured, or one with no driver written for it yet — and the caller says so
/// rather than failing: search and the barcode scanner are how the app is used when no
/// model will answer.
nonisolated enum Estimators {
    /// The model that will read a line, or `nil` when none will.
    ///
    /// `nil` means one of two things the caller need not tell apart: the chosen provider
    /// has no driver written for it, or it has one and has not been configured yet. Either
    /// way the composer says so in the one sentence it has, and search and the scanner
    /// still work. Asking for the driver is also how `LineResolver` learns whether a line
    /// can be read at all, which is better than reading the provider setting a second time
    /// and risking a different answer.
    ///
    /// A switch rather than a guard, so that adding a provider is a compile error here. The
    /// searches are passed in because they belong to the device — the tables and the store
    /// live on the main actor and this type has no business reaching for them.
    @MainActor
    static func driver(searching searcher: any LineSearching) -> (any LineDriving)? {
        switch chosen() {
        case .onDevice:
            return nil
        case .anthropic:
            let settings = anthropicSettings()
            guard settings.isUsable else { return nil }
            return AnthropicLineResolver(
                settings: settings, key: EstimationKeychain.read(.anthropic), searcher: searcher
            )
        case .remote:
            let settings = remoteSettings()
            guard settings.isUsable else { return nil }
            return OpenAICompatibleLineResolver(
                settings: settings, key: EstimationKeychain.read(.openAICompatible),
                searcher: searcher
            )
        }
    }

    /// Defaults to the device, which has sent nothing anywhere and needs no key. It is no
    /// longer true that a first run needs no decision before everything works: the device
    /// cannot read a typed line, so the composer asks for a provider to be chosen, in the
    /// one sentence it has to say it in. Defaulting to a remote provider instead would
    /// trade that for a first run that needs a key pasted in, which is worse.
    private static func chosen() -> EstimationProvider {
        guard let raw = UserDefaults.standard.string(forKey: EstimationProvider.key),
              let provider = EstimationProvider(rawValue: raw)
        else { return .onDevice }
        return provider
    }

    private static func remoteSettings() -> RemoteEstimatorSettings {
        let defaults = UserDefaults.standard
        return RemoteEstimatorSettings(
            baseURL: defaults.string(forKey: RemoteEstimatorSettings.baseURLKey) ?? "",
            model: defaults.string(forKey: RemoteEstimatorSettings.modelKey) ?? "",
            sendsPhotos: defaults.bool(forKey: RemoteEstimatorSettings.sendsPhotosKey)
        )
    }

    private static func anthropicSettings() -> AnthropicSettings {
        let defaults = UserDefaults.standard
        return AnthropicSettings(
            baseURL: defaults.string(forKey: AnthropicSettings.baseURLKey) ?? "",
            model: defaults.string(forKey: AnthropicSettings.modelKey) ?? "",
            sendsPhotos: defaults.bool(forKey: AnthropicSettings.sendsPhotosKey)
        )
    }
}
