import Foundation

/// The marketing version and build number as Settings shows them: "Version 0.1 (1)".
nonisolated enum AppVersion {
    /// Read from `Bundle.main` at the time of the call.
    static var display: String {
        let info = Bundle.main.infoDictionary
        return string(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String
        )
    }

    /// "Version 0.1 (1)". The build is left out when it is missing, and a missing
    /// version reads "Version unknown" rather than an empty line.
    static func string(version: String?, build: String?) -> String {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !version.isEmpty else { return "Version unknown" }
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }
}
