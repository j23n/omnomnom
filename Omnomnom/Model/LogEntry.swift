import Foundation
import SwiftData

/// One logged food: what, how much, when, and the frozen nutrition snapshot that
/// HealthKit received. `id` is the root of every sync identifier written to Health.
/// The snapshot is stored as eight flat optional scalars; `snapshot` packs them.
@Model
final class LogEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var mealSlotRaw: String = MealSlot.snack.rawValue
    /// Name at log time; never changes even if the food is renamed or deleted.
    var foodName: String = ""
    var grams: Double = 0
    var snapshotEnergy: Double?
    var snapshotProtein: Double?
    var snapshotCarbohydrates: Double?
    var snapshotFatTotal: Double?
    var snapshotFatSaturated: Double?
    var snapshotFiber: Double?
    var snapshotSugar: Double?
    var snapshotSodium: Double?
    /// Bumped on every edit and sent as `HKMetadataKeySyncVersion`.
    var syncVersion: Int = 1
    /// Raw `Nutrient` values this app last saved to Health.
    var writtenNutrients: [String] = []
    /// Raw `Nutrient` values reconciliation last saw in Health. Equals `writtenNutrients` until then.
    var presentNutrients: [String] = []
    /// Set when a local delete could not be mirrored to Health.
    var orphaned: Bool = false
    var food: Food?

    /// Relate to a `Food` after `context.insert(entry)`, not here.
    init(timestamp: Date, mealSlot: MealSlot, foodName: String, grams: Double, snapshot: Nutrition) {
        self.id = UUID()
        self.timestamp = timestamp
        self.mealSlotRaw = mealSlot.rawValue
        self.foodName = foodName
        self.grams = grams
        self.syncVersion = 1
        self.writtenNutrients = []
        self.presentNutrients = []
        self.orphaned = false
        self.snapshot = snapshot
    }

    /// Nutrition at log time; never recomputed.
    var snapshot: Nutrition {
        get {
            Nutrition(
                energy: snapshotEnergy, protein: snapshotProtein, carbohydrates: snapshotCarbohydrates,
                fatTotal: snapshotFatTotal, fatSaturated: snapshotFatSaturated, fiber: snapshotFiber,
                sugar: snapshotSugar, sodium: snapshotSodium
            )
        }
        set {
            snapshotEnergy = newValue.energy
            snapshotProtein = newValue.protein
            snapshotCarbohydrates = newValue.carbohydrates
            snapshotFatTotal = newValue.fatTotal
            snapshotFatSaturated = newValue.fatSaturated
            snapshotFiber = newValue.fiber
            snapshotSugar = newValue.sugar
            snapshotSodium = newValue.sodium
        }
    }

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .snack }
        set { mealSlotRaw = newValue.rawValue }
    }

    var written: Set<Nutrient> {
        get { Set(writtenNutrients.compactMap(Nutrient.init(rawValue:))) }
        set { writtenNutrients = newValue.map(\.rawValue).sorted() }
    }

    var present: Set<Nutrient> {
        get { Set(presentNutrients.compactMap(Nutrient.init(rawValue:))) }
        set { presentNutrients = newValue.map(\.rawValue).sorted() }
    }

    var healthState: HealthState {
        HealthState.derive(written: written, present: present, orphaned: orphaned)
    }
}
