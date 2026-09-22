import Foundation

/// Where an entry stands relative to Health, derived from the two nutrient sets on `LogEntry`.
nonisolated enum HealthState: String, Sendable {
    /// Everything this app wrote is still in Health.
    case synced
    /// Health still has some, but not all, of the samples this app wrote.
    case partial
    /// Health has none of the samples this app wrote.
    case gone
    /// Nothing of this entry ever reached Health: no nutrient was authorized when it was
    /// logged, or the write failed. A fact about this entry, not about Health right now.
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

    /// States the user can act on from the entry's editor: write the entry to Health or
    /// remove it here. `unauthorized` is one of them: an entry that never reached Health
    /// can be written now, and without that a failed write would be unrecoverable.
    var needsAttention: Bool {
        switch self {
        case .partial, .gone, .unauthorized: true
        case .synced, .orphaned: false
        }
    }

    /// Short badge text for states worth showing on Today; `nil` for `synced`. The two
    /// states Health is short of read apart rather than only differing in tense: `gone`
    /// was in Health and went, `unauthorized` never arrived.
    var badgeText: String? {
        switch self {
        case .synced: nil
        case .partial: "Partly in Health"
        case .gone: "No longer in Health"
        case .unauthorized: "Not in Health"
        case .orphaned: "Only in Health"
        }
    }
}
