import Foundation

/// Snapshot of what Health lets this app write, for the Settings screen.
/// Only write status exists; iOS never reports read status, so nothing here claims it.
nonisolated struct HealthAuthorization: Hashable, Sendable {
    let isAvailable: Bool
    let authorized: Set<Nutrient>

    static let unavailable = HealthAuthorization(isAvailable: false, authorized: [])

    /// Loads the current state from `health`.
    static func current(from health: any HealthWriting) async -> HealthAuthorization {
        guard health.isAvailable else { return .unavailable }
        return HealthAuthorization(isAvailable: true, authorized: await health.authorizedNutrients())
    }

    func isAuthorized(_ nutrient: Nutrient) -> Bool {
        authorized.contains(nutrient)
    }

    /// "Writing allowed" or "Writing not allowed" for one nutrient.
    func writeStatusText(for nutrient: Nutrient) -> String {
        isAuthorized(nutrient) ? "Writing allowed" : "Writing not allowed"
    }

    /// One-line summary for the Settings row.
    var summary: String {
        guard isAvailable else { return "Health is not available on this device" }
        switch authorized.count {
        case 0: return "No nutrient can be written"
        case Nutrient.allCases.count: return "All eight nutrients can be written"
        default: return "\(authorized.count) of \(Nutrient.allCases.count) nutrients can be written"
        }
    }
}
