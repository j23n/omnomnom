import Testing
@testable import Omnomnom

struct SnapshotTests {
    @Test func snapshotScalesPer100gValues() {
        let per100g = Nutrition(energy: 130, protein: 2.69, carbohydrates: 28.2, sodium: 1)
        let snapshot = SnapshotMath.snapshot(per100g: per100g, grams: 158)
        #expect(snapshot.energy.map { abs($0 - 205.4) < 0.0001 } == true)
        #expect(snapshot.sodium.map { abs($0 - 1.58) < 0.0001 } == true)
        #expect(snapshot.fiber == nil)
    }

    @Test func totalOfNothingReadsZeroEverywhere() {
        let total = SnapshotMath.total(of: [])
        for nutrient in Nutrient.allCases {
            #expect(total[nutrient] == 0)
        }
    }

    @Test func totalSumsAndFillsMissingWithZero() {
        let total = SnapshotMath.total(of: [
            Nutrition(energy: 100, fiber: 2),
            Nutrition(energy: 50, sugar: 3),
        ])
        #expect(total.energy == 150)
        #expect(total.fiber == 2)
        #expect(total.sugar == 3)
        #expect(total.sodium == 0)
    }

    @Test func healthStateTable() {
        let written: Set<Nutrient> = [.energy, .protein]
        #expect(HealthState.derive(written: written, present: written, orphaned: false) == .synced)
        #expect(HealthState.derive(written: written, present: [.energy], orphaned: false) == .partial)
        #expect(HealthState.derive(written: written, present: [], orphaned: false) == .gone)
        #expect(HealthState.derive(written: [], present: [], orphaned: false) == .unauthorized)
        #expect(HealthState.derive(written: written, present: written, orphaned: true) == .orphaned)
    }

    /// Every state but `synced` is named on the row, and none of the texts claims more
    /// than the state knows: an empty written set means the entry is not in Health,
    /// whether the permission was missing or the write failed.
    @Test func badgeTextNamesEveryStateButSynced() {
        #expect(HealthState.synced.badgeText == nil)
        #expect(HealthState.partial.badgeText == "Partly in Health")
        #expect(HealthState.gone.badgeText == "No longer in Health")
        #expect(HealthState.unauthorized.badgeText == "Not in Health")
        #expect(HealthState.orphaned.badgeText == "Only in Health")
    }

    /// The editor offers to write the entry to Health for every state where Health is
    /// short of it, including one that never got there, so a failed write is recoverable.
    @Test func needsAttentionCoversEveryStateHealthIsShortOf() {
        #expect(HealthState.partial.needsAttention)
        #expect(HealthState.gone.needsAttention)
        #expect(HealthState.unauthorized.needsAttention)
        #expect(!HealthState.synced.needsAttention)
        #expect(!HealthState.orphaned.needsAttention)
    }
}
