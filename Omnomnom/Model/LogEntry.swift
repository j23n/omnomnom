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
    /// The mass logged, in grams; 0 for an entry that is counted only in millilitres.
    var grams: Double = 0
    /// The volume logged, in millilitres; `nil` for an entry that has none. A recipe
    /// entry holds both when its ingredients do, and the two are never added together.
    var millilitres: Double?
    /// Raw `FoodMeasure` of the food at log time, frozen like the name and the snapshot:
    /// correcting the food's unit later never reinterprets what is already logged. It
    /// says which of the two columns a directly logged food filled; a recipe entry is
    /// counted in servings and reads both.
    var measureRaw: String = FoodMeasure.mass.rawValue
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
    /// True for an entry the user confirmed from an on-device estimate rather than a food.
    var isEstimate: Bool = false
    /// What the line called this food, when a line is what logged it; `nil` for an entry
    /// picked, repeated or copied, where the user named the food themselves.
    ///
    /// Kept because the app cannot otherwise say what it was answering. A row reading
    /// *Oat flakes* is unarguable next to the word "oats" and wrong next to "oat milk",
    /// and only one of those two is a thing the person can see.
    var wording: String?
    /// Whether the food was matched for the user rather than named by them, and the match
    /// was not a certainty.
    ///
    /// What the mark on the row is drawn from. It is about how the food was arrived at and
    /// never about the food: an entry carrying this is as logged, as written to Health and
    /// as real as any other, and the mark asks a question rather than withholding anything.
    /// Cleared the moment the user says it is right, which is the one thing that makes the
    /// mark finite.
    var guessed: Bool = false
    /// Raw `EntryOrigin`: how this entry came to exist. Defaulted, so entries written
    /// before the app recorded it read as picked, which is what they were.
    var originRaw: String = EntryOrigin.picked.rawValue
    /// Servings logged, for a recipe entry; `nil` for a food. `rawAmount` holds what
    /// those servings, or that food, came to either way.
    var servings: Double?
    var food: Food?
    /// The recipe this was logged from, for display only; the snapshot never recomputes.
    var recipe: Recipe?
    /// The plate this entry was estimated from, shared with the other entries of that
    /// estimate; `nil` for an entry logged from a food or recipe, whose photo is theirs.
    var photo: Photo?

    /// Relate to a `Food` or `Recipe` after `context.insert(entry)`, not here.
    init(
        timestamp: Date, mealSlot: MealSlot, foodName: String, amount: RawAmount,
        snapshot: Nutrition, measure: FoodMeasure = .mass
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.mealSlotRaw = mealSlot.rawValue
        self.foodName = foodName
        self.measureRaw = measure.rawValue
        self.rawAmount = amount
        self.syncVersion = 1
        self.writtenNutrients = []
        self.presentNutrients = []
        self.orphaned = false
        self.isEstimate = false
        self.guessed = false
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

    /// How the entry came to exist; see `EntryOrigin`.
    var origin: EntryOrigin {
        get { EntryOrigin(rawValue: originRaw) ?? .picked }
        set { originRaw = newValue.rawValue }
    }

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .snack }
        set { mealSlotRaw = newValue.rawValue }
    }

    /// The unit the amount was logged in, as the food read at that moment.
    var measure: FoodMeasure {
        get { FoodMeasure(rawValue: measureRaw) ?? .mass }
        set { measureRaw = newValue.rawValue }
    }

    /// What was logged, mass and volume apart. A volume of nothing is stored as `nil`
    /// rather than 0, so an entry that has no volume part says so.
    var rawAmount: RawAmount {
        get { RawAmount(grams: grams, millilitres: millilitres ?? 0) }
        set {
            grams = newValue.grams
            millilitres = newValue.millilitres > 0 ? newValue.millilitres : nil
        }
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

    /// Nutrients this app wrote that Health no longer holds, in display order.
    var missingFromHealth: [Nutrient] {
        let written = self.written
        let present = self.present
        return Nutrient.allCases.filter { written.contains($0) && !present.contains($0) }
    }

    /// The photo to show on the row: the entry's own, else the recipe's, else the food's.
    var displayPhoto: Photo? {
        photo ?? recipe?.photo ?? food?.photo
    }

    /// Call before `context.delete(entry)`: deletes the entry's own photo unless another
    /// entry of the same estimate still shows it. A recipe's or food's photo is theirs
    /// and is never touched here.
    func releasePhoto(in context: ModelContext) {
        guard let photo else { return }
        let sharedWithOthers = (photo.entries ?? []).contains { $0.id != id && !$0.isDeleted }
        if !sharedWithOthers {
            context.delete(photo)
        }
    }
}
