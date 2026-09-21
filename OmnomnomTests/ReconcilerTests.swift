import Foundation
import Testing
@testable import Omnomnom

struct ReconcilerTests {
    private let a = UUID()
    private let b = UUID()
    private let all = Set(Nutrient.allCases)

    private let day: TimeInterval = 86_400
    private let runStart = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Window defaults to everything: no readable-since limit and a run start far ahead.
    private func changes(
        added: [String] = [], deleted: [String] = [], fullyRead: Set<Nutrient> = [],
        readableSince: [Nutrient: Date] = [:], runStart: Date = .distantFuture
    ) -> HealthChanges {
        HealthChanges(
            added: added, deleted: deleted, anchors: .empty,
            fullyRead: fullyRead, readableSince: readableSince, runStart: runStart
        )
    }

    private func id(_ entry: UUID, _ nutrient: Nutrient) -> String {
        SyncIdentifier.make(entryID: entry, nutrient: nutrient)
    }

    @Test func partialDeleteRemovesOnlyThoseNutrients() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let plan = Reconciler.plan(entries: entries, changes: changes(deleted: [id(a, .protein), id(a, .fiber)]))
        #expect(plan.present[a] == all.subtracting([.protein, .fiber]))
    }

    @Test func fullDeleteLeavesPresentEmpty() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let deleted = Nutrient.allCases.map { id(a, $0) } + [SyncIdentifier.make(mealFor: a)]
        let plan = Reconciler.plan(entries: entries, changes: changes(deleted: deleted))
        #expect(plan.present[a] == Set<Nutrient>())
    }

    @Test func mealOnlyDeleteChangesNothing() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let plan = Reconciler.plan(entries: entries, changes: changes(deleted: [SyncIdentifier.make(mealFor: a)]))
        #expect(plan.isEmpty)
    }

    @Test func addedIdentifiersRestoreWrittenNutrients() {
        let entries = [ReconcileEntry(id: a, written: all, present: [.energy])]
        let added = Nutrient.allCases.map { id(a, $0) } + [SyncIdentifier.make(mealFor: a)]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: added))
        #expect(plan.present[a] == all)
    }

    @Test func addedNutrientNotInWrittenIsIgnored() {
        let entries = [ReconcileEntry(id: a, written: [.energy], present: [.energy])]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: [id(a, .sodium)]))
        #expect(plan.isEmpty)
    }

    @Test func replacedSampleEndsUpPresent() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: [id(a, .energy)], deleted: [id(a, .energy)]))
        #expect(plan.isEmpty)
    }

    @Test func unknownEntriesAndGarbageAreIgnored() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let plan = Reconciler.plan(entries: entries, changes: changes(deleted: [id(b, .energy), "garbage", "\(a.uuidString).caffeine"]))
        #expect(plan.isEmpty)
        #expect(Reconciler.affectedEntryIDs(in: changes(deleted: [id(b, .energy), "garbage"])) == [b])
    }

    @Test func onlyChangedEntriesAppearInThePlan() {
        let entries = [
            ReconcileEntry(id: a, written: all, present: all),
            ReconcileEntry(id: b, written: [.energy], present: [.energy]),
        ]
        let plan = Reconciler.plan(entries: entries, changes: changes(deleted: [id(b, .energy)]))
        #expect(plan.present.keys.sorted { $0.uuidString < $1.uuidString } == [b])
        #expect(plan.present[b] == Set<Nutrient>())
        #expect(HealthState.derive(written: [.energy], present: [], orphaned: false) == .gone)
    }

    @Test func fullReadDropsWrittenNutrientsThatWereNotSeen() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let seenElsewhere = id(b, .protein)
        let plan = Reconciler.plan(entries: entries, changes: changes(added: [id(a, .energy), seenElsewhere], fullyRead: [.energy, .protein]))
        #expect(plan.present[a] == all.subtracting([.protein]))
        #expect(plan.unpruned.isEmpty)
    }

    @Test func fullReadKeepsNutrientsThatWereSeen() {
        let entries = [ReconcileEntry(id: a, written: all, present: all)]
        let added = Nutrient.allCases.map { id(a, $0) }
        let plan = Reconciler.plan(entries: entries, changes: changes(added: added, fullyRead: all))
        #expect(plan.isEmpty)
    }

    @Test func fullReadLeavesOtherNutrientsAndEntriesAlone() {
        let entries = [
            ReconcileEntry(id: a, written: all, present: all),
            ReconcileEntry(id: b, written: [.fiber], present: [.fiber]),
        ]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: [id(UUID(), .sodium)], fullyRead: [.sodium]))
        #expect(plan.present[a] == all.subtracting([.sodium]))
        #expect(plan.present[b] == nil)
        #expect(plan.present.count == 1)
        #expect(plan.unpruned.isEmpty)
    }

    @Test func fullReadWithNothingWrittenChangesNothing() {
        let entries = [ReconcileEntry(id: a, written: [], present: [])]
        let plan = Reconciler.plan(entries: entries, changes: changes(fullyRead: all))
        #expect(plan.isEmpty)
    }

    @Test func fullReadPrunesOnlyEntriesInsideTheReadableWindow() {
        let since = runStart.addingTimeInterval(-7 * day)
        let older = ReconcileEntry(id: a, written: all, present: all, timestamp: since.addingTimeInterval(-day))
        let inside = ReconcileEntry(id: b, written: all, present: all, timestamp: since.addingTimeInterval(day))
        let atBoundary = ReconcileEntry(id: UUID(), written: all, present: all, timestamp: since)
        let newer = ReconcileEntry(id: UUID(), written: all, present: all, timestamp: runStart.addingTimeInterval(1))
        let seen = UUID()
        let plan = Reconciler.plan(
            entries: [older, inside, atBoundary, newer, ReconcileEntry(id: seen, written: [.energy], present: [.energy], timestamp: since.addingTimeInterval(day))],
            changes: changes(added: [id(seen, .energy)], fullyRead: [.energy], readableSince: [.energy: since], runStart: runStart)
        )
        #expect(plan.present[older.id] == nil)
        #expect(plan.present[newer.id] == nil)
        #expect(plan.present[inside.id] == all.subtracting([.energy]))
        #expect(plan.present[atBoundary.id] == all.subtracting([.energy]))
        #expect(plan.present[seen] == nil)
        #expect(plan.unpruned.isEmpty)
    }

    @Test func fullReadWithNoOwnIdentifierForTheNutrientDoesNotPrune() {
        let entries = [
            ReconcileEntry(id: a, written: all, present: all, timestamp: runStart.addingTimeInterval(-day)),
            ReconcileEntry(id: b, written: all, present: all, timestamp: runStart.addingTimeInterval(-day)),
        ]
        let foreignOnly = ["garbage", "\(UUID().uuidString).meal", id(UUID(), .protein)]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: foreignOnly, fullyRead: [.energy, .protein], runStart: runStart))
        #expect(plan.unpruned == [.energy])
        #expect(plan.present[a] == all.subtracting([.protein]))
        #expect(plan.present[b] == all.subtracting([.protein]))
        let nobodyWrote = Reconciler.plan(entries: [ReconcileEntry(id: a, written: [.fiber], present: [.fiber])], changes: changes(fullyRead: [.energy]))
        #expect(nobodyWrote.isEmpty)
        #expect(nobodyWrote.unpruned.isEmpty)
    }

    @Test func unauthorizedEntryNeverGainsNutrients() {
        let entries = [ReconcileEntry(id: a, written: [], present: [])]
        let plan = Reconciler.plan(entries: entries, changes: changes(added: [id(a, .energy)]))
        #expect(plan.isEmpty)
    }
}
