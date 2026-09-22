import Foundation

/// Outcome of logging one entry. The entry always exists locally; `healthError`
/// says why Health did not get it, `storeError` why the local record could not note
/// what was written, and an empty `written` means nothing was authorized.
nonisolated struct LogResult: Hashable, Sendable {
    let entryID: UUID
    let written: Set<Nutrient>
    let healthError: String?
    let storeError: String?

    /// Non-blocking message for Today, or `nil` when everything went through.
    var bannerMessage: String? {
        if let healthError {
            return "Logged here only. Health didn't accept it: \(healthError)"
        }
        if let storeError {
            return "Saved to Health but could not update the local record: \(storeError)"
        }
        if written.isEmpty {
            return "Logged here only. Health didn't accept it."
        }
        return nil
    }
}

/// Outcome of deleting one entry, which mirrors to Health first.
nonisolated enum DeleteOutcome: Hashable, Sendable {
    /// Removed from Health (where it existed) and locally.
    case deleted
    /// Health refused the delete; the row stays, flagged `orphaned`. Deleting it again removes it locally.
    case orphaned
    /// Nothing was changed.
    case failed(String)

    var bannerMessage: String? {
        switch self {
        case .deleted:
            nil
        case .orphaned:
            "Health no longer lets this app delete its data. Delete again to remove the entry here; remove it in Health separately."
        case .failed(let message):
            "Could not delete: \(message)"
        }
    }
}
