import Foundation

/// The read side of the Health surface: change observation, anchored change feeds and
/// day reads, all in value types. `HealthStore` implements it; `UnavailableHealth` is
/// the no-op used in previews and when Health is absent. No `HK` type appears here.
nonisolated protocol HealthObserving: Sendable {
    /// Registers one observer query per nutrient type with immediate background delivery.
    /// `onChange` runs on every wake and finishes before HealthKit's completion handler is
    /// called. A second call is a no-op: the queries from the first call stay registered.
    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws

    /// Objects added and deleted since `anchors`, as sync identifiers, plus the anchors
    /// to store for the next call. A missing anchor means the whole history of that type.
    /// Objects without a sync identifier are left out.
    func changes(since anchors: HealthAnchors) async throws -> HealthChanges

    /// Every dietary sample starting in `interval`, whoever wrote it.
    func samples(in interval: DateInterval) async throws -> [HealthNutritionSample]
}

/// One batch of anchored-query results, reduced to the identifiers reconciliation reads.
nonisolated struct HealthChanges: Hashable, Sendable {
    /// Sync identifiers of objects that now exist in Health.
    let added: [String]
    /// Sync identifiers of objects Health no longer holds.
    let deleted: [String]
    /// Anchors to persist once the batch has been applied.
    let anchors: HealthAnchors
    /// Nutrients whose type was read from no anchor through to the end, so `added` is the
    /// complete list of that type's objects: anything written but absent from it is gone.
    /// A read from an anchor only reports changes since then and does not qualify.
    let fullyRead: Set<Nutrient>
    /// Earliest sample date the user let this app read, per nutrient; a type missing here
    /// reads as `.distantPast`. Older entries cannot be judged by a full read.
    let readableSince: [Nutrient: Date]
    /// Taken before the first query: entries logged after it were not covered by the read.
    let runStart: Date

    init(
        added: [String], deleted: [String], anchors: HealthAnchors,
        fullyRead: Set<Nutrient> = [], readableSince: [Nutrient: Date] = [:], runStart: Date = .distantFuture
    ) {
        self.added = added
        self.deleted = deleted
        self.anchors = anchors
        self.fullyRead = fullyRead
        self.readableSince = readableSince
        self.runStart = runStart
    }

    /// Whether a full read of `nutrient` says anything about an entry logged at `timestamp`.
    func fullReadCovers(_ nutrient: Nutrient, at timestamp: Date) -> Bool {
        (readableSince[nutrient] ?? .distantPast) <= timestamp && timestamp < runStart
    }

    /// No change, anchors untouched.
    static func unchanged(anchors: HealthAnchors) -> HealthChanges {
        HealthChanges(added: [], deleted: [], anchors: anchors)
    }

    var isEmpty: Bool { added.isEmpty && deleted.isEmpty }
}

/// One dietary quantity sample as read back from Health.
nonisolated struct HealthNutritionSample: Hashable, Sendable {
    let nutrient: Nutrient
    /// Amount in `nutrient.unit`.
    let value: Double
    let start: Date
    /// True when this app's bundle wrote the sample, on this or another device. Whether a
    /// local entry mirrors it is decided by its sync identifier, not by this flag.
    let isOwnBundle: Bool
    /// Display name of the writing source, as Health shows it.
    let sourceName: String
    let syncIdentifier: String?
    /// `HKMetadataKeyFoodType`, when the writer set it on the sample.
    let foodType: String?
}
