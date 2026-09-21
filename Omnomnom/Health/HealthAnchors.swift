import Foundation
import os

/// Opaque anchors for the anchored queries, one per HealthKit type identifier, holding
/// the archived bytes of an `HKQueryAnchor`. Plain data here so nothing outside the
/// Health layer imports HealthKit; `HealthAnchorCodec` turns the bytes into anchors.
nonisolated struct HealthAnchors: Hashable, Sendable {
    /// Archived anchor per type identifier. A missing key means "from the beginning".
    private(set) var data: [String: Data]

    init(data: [String: Data] = [:]) {
        self.data = data
    }

    /// No anchor for any type: every query reads the full history.
    static let empty = HealthAnchors()

    /// Key in `UserDefaults` under which the JSON-encoded dictionary lives.
    static let defaultsKey = "healthAnchors"

    subscript(typeIdentifier: String) -> Data? {
        get { data[typeIdentifier] }
        set { data[typeIdentifier] = newValue }
    }

    /// The dictionary as JSON, for storage.
    func encoded() throws -> Data {
        try JSONEncoder().encode(data)
    }

    /// Decodes what `encoded()` produced.
    init(json: Data) throws {
        self.data = try JSONDecoder().decode([String: Data].self, from: json)
    }

    /// The stored anchors, or `empty` when nothing was stored or it no longer decodes;
    /// a decode failure is logged and costs one full re-read, never a launch failure.
    static func load(from defaults: UserDefaults) -> HealthAnchors {
        guard let json = defaults.data(forKey: defaultsKey) else { return .empty }
        do {
            return try HealthAnchors(json: json)
        } catch {
            AppLog.health.error("stored anchors unreadable, reading full history: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    func save(to defaults: UserDefaults) throws {
        defaults.set(try encoded(), forKey: Self.defaultsKey)
    }
}
