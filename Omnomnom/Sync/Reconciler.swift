import Foundation

/// The sync state of one entry, copied out of the store so the plan is computed on values.
nonisolated struct ReconcileEntry: Hashable, Sendable {
    let id: UUID
    let written: Set<Nutrient>
    let present: Set<Nutrient>
    /// When the entry was logged; decides whether a full read covered it.
    let timestamp: Date

    init(id: UUID, written: Set<Nutrient>, present: Set<Nutrient>, timestamp: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.id = id
        self.written = written
        self.present = present
        self.timestamp = timestamp
    }
}

/// The new `present` set for every entry the changes moved, keyed by entry id.
/// Entries whose set stayed the same are left out.
nonisolated struct ReconcilePlan: Hashable, Sendable {
    let present: [UUID: Set<Nutrient>]
    /// Fully read nutrients that were not pruned because the read returned no own
    /// identifier for them although a local entry wrote them; the service logs these.
    let unpruned: Set<Nutrient>

    init(present: [UUID: Set<Nutrient>], unpruned: Set<Nutrient> = []) {
        self.present = present
        self.unpruned = unpruned
    }

    static let empty = ReconcilePlan(present: [:])

    var isEmpty: Bool { present.isEmpty }
}

/// Pure rules turning one batch of Health changes into new `present` sets.
nonisolated enum Reconciler {
    /// Ids of every entry the changes could concern, so the service fetches only those rows.
    static func affectedEntryIDs(in changes: HealthChanges) -> Set<UUID> {
        Set((changes.deleted + changes.added).compactMap { SyncIdentifier.parse($0)?.entryID })
    }

    /// Deletions first, then additions, so a sample replaced in place (old object deleted,
    /// new object added under the same identifier) ends up present.
    ///
    /// - A deleted nutrient identifier removes that nutrient from `present`.
    /// - A deleted meal identifier alone changes nothing; the samples decide.
    /// - An added nutrient identifier restores that nutrient only if the entry wrote it.
    /// - For a nutrient in `fullyRead`, `added` is exhaustive: an entry that wrote it but
    ///   has no added identifier for it loses it, since HealthKit never reports deletions
    ///   that happened before the first anchor. Only entries the read covered qualify
    ///   (`readableSince[N] <= timestamp < runStart`): the user may have granted a window
    ///   of recent data, and the absence of older samples proves nothing. A full read
    ///   that returned no own identifier for N at all while some entry wrote N is not
    ///   trusted either; such nutrients are reported in `unpruned`.
    /// - Identifiers that do not parse, or name no entry in `entries`, are ignored.
    static func plan(entries: [ReconcileEntry], changes: HealthChanges) -> ReconcilePlan {
        var present = Dictionary(entries.map { ($0.id, $0.present) }, uniquingKeysWith: { first, _ in first })
        let written = Dictionary(entries.map { ($0.id, $0.written) }, uniquingKeysWith: { first, _ in first })
        for id in changes.deleted {
            guard let parsed = SyncIdentifier.parse(id), case .nutrient(let nutrient) = parsed.part else { continue }
            present[parsed.entryID]?.remove(nutrient)
        }
        for id in changes.added {
            guard let parsed = SyncIdentifier.parse(id), case .nutrient(let nutrient) = parsed.part else { continue }
            guard written[parsed.entryID]?.contains(nutrient) == true else { continue }
            present[parsed.entryID]?.insert(nutrient)
        }
        var unpruned = Set<Nutrient>()
        if !changes.fullyRead.isEmpty {
            let addedIDs = Set(changes.added)
            let seenNutrients = Set(changes.added.compactMap { id -> Nutrient? in
                guard case .nutrient(let nutrient)? = SyncIdentifier.parse(id)?.part else { return nil }
                return nutrient
            })
            for nutrient in changes.fullyRead {
                let writers = entries.filter { $0.written.contains(nutrient) }
                guard !writers.isEmpty else { continue }
                guard seenNutrients.contains(nutrient) else {
                    unpruned.insert(nutrient)
                    continue
                }
                for entry in writers where changes.fullReadCovers(nutrient, at: entry.timestamp) {
                    if !addedIDs.contains(SyncIdentifier.make(entryID: entry.id, nutrient: nutrient)) {
                        present[entry.id]?.remove(nutrient)
                    }
                }
            }
        }
        var changed: [UUID: Set<Nutrient>] = [:]
        for entry in entries {
            if let updated = present[entry.id], updated != entry.present {
                changed[entry.id] = updated
            }
        }
        return ReconcilePlan(present: changed, unpruned: unpruned)
    }
}
