import Foundation

/// Where an entry stands relative to Health, derived from the two nutrient sets on `LogEntry`.
nonisolated enum HealthState: String, Sendable {
    /// Everything this app wrote is still in Health.
    case synced
    /// Health still has some, but not all, of the samples this app wrote.
    case partial
    /// Health has none of the samples this app wrote.
    case gone
    /// Nothing was written because no nutrient type was authorized.
    case unauthorized
    /// The entry was deleted locally but the samples could not be removed from Health.
    case orphaned

    /// Derives the state per the table in PLAN.md.
    ///
    /// `present` holding nutrients that are not in `written` cannot arise from this
    /// app's own writes (reconciliation only ever sees samples it saved); if it does,
    /// Health has at least everything that was written, so the entry counts as `synced`.
    static func derive(written: Set<Nutrient>, present: Set<Nutrient>, orphaned: Bool) -> HealthState {
        if orphaned { return .orphaned }
        if written.isEmpty { return .unauthorized }
        if present == written { return .synced }
        if present.isEmpty { return .gone }
        if present.isStrictSubset(of: written) { return .partial }
        return .synced
    }

    /// Short badge text for states worth showing on Today; `nil` for `synced`.
    var badge: String? {
        switch self {
        case .synced: nil
        case .partial: "Partly in Health"
        case .gone: "Not in Health"
        case .unauthorized: "Not written"
        case .orphaned: "Left in Health"
        }
    }
}
