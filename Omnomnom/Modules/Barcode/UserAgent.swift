import Foundation

/// The User-Agent Open Food Facts asks every client to send: the app name and version
/// plus a contact URL. Requests without one are rate-limited.
nonisolated enum UserAgent {
    static let contactURL = "https://github.com/j23n/omnomnom"

    /// "Omnomnom/0.1 (https://github.com/j23n/omnomnom)"; the version is left out when unknown.
    static func string(appVersion: String?) -> String {
        let version = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let product = version.isEmpty ? "Omnomnom" : "Omnomnom/\(version)"
        return "\(product) (\(contactURL))"
    }

    /// Composed from `CFBundleShortVersionString` of `bundle`.
    static func current(bundle: Bundle = .main) -> String {
        string(appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }
}
