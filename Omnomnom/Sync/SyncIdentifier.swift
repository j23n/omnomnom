import Foundation

/// The identifier scheme shared by every object this app saves to Health:
/// `<entry uuid>.<nutrient>` for a sample and `<entry uuid>.meal` for the correlation.
/// The one place that makes and parses them, so reconciliation reads exactly what the
/// writer wrote.
nonisolated enum SyncIdentifier {
    /// What one identifier names within an entry.
    enum Part: Hashable, Sendable {
        case nutrient(Nutrient)
        case meal
    }

    /// Suffix of the correlation's identifier; no `Nutrient` raw value collides with it.
    static let mealSuffix = "meal"

    static func make(entryID: UUID, nutrient: Nutrient) -> String {
        "\(entryID.uuidString).\(nutrient.rawValue)"
    }

    static func make(mealFor entryID: UUID) -> String {
        "\(entryID.uuidString).\(mealSuffix)"
    }

    /// The entry and part an identifier names, or `nil` for anything this app did not write.
    static func parse(_ id: String) -> (entryID: UUID, part: Part)? {
        let pieces = id.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2, let entryID = UUID(uuidString: String(pieces[0])) else { return nil }
        let suffix = String(pieces[1])
        if suffix == mealSuffix { return (entryID, .meal) }
        guard let nutrient = Nutrient(rawValue: suffix) else { return nil }
        return (entryID, .nutrient(nutrient))
    }
}
