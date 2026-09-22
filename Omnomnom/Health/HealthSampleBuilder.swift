import Foundation

/// Description of one `HKQuantitySample` to be created, as a plain value.
nonisolated struct SampleSpec: Hashable, Sendable {
    let nutrient: Nutrient
    let value: Double
    let unit: NutrientUnit
    let syncIdentifier: String
    let syncVersion: Int
}

/// Description of the `HKCorrelation` of type food that wraps the samples.
nonisolated struct CorrelationSpec: Hashable, Sendable {
    let syncIdentifier: String
    let syncVersion: Int
    let foodType: String
    let mealSlot: MealSlot
    let start: Date
    let samples: [SampleSpec]
}

/// Pure translation from a `HealthWriteRequest` to sample and correlation specs.
/// Applies the sync identifier scheme and the partial-authorization rule from PLAN.md.
nonisolated enum HealthSampleBuilder {
    /// Custom metadata key on the correlation carrying the meal slot's raw value.
    static let mealSlotMetadataKey = "com.j23n.omnomnom.mealSlot"

    /// Every sync identifier one entry may hold in Health: one per written nutrient, in
    /// `Nutrient` order, plus the correlation. Empty when nothing was written, since no
    /// correlation exists without at least one sample. The scheme lives in `SyncIdentifier`.
    static func syncIdentifiers(entryID: UUID, nutrients: Set<Nutrient>) -> [String] {
        let samples = Nutrient.allCases.filter(nutrients.contains).map { SyncIdentifier.make(entryID: entryID, nutrient: $0) }
        guard !samples.isEmpty else { return [] }
        return samples + [SyncIdentifier.make(mealFor: entryID)]
    }

    /// One spec per nutrient that has a value and is authorized, in `Nutrient` order.
    static func samples(for request: HealthWriteRequest, authorized: Set<Nutrient>) -> [SampleSpec] {
        Nutrient.allCases.compactMap { nutrient in
            guard authorized.contains(nutrient), let value = request.nutrition[nutrient] else { return nil }
            return SampleSpec(
                nutrient: nutrient,
                value: value,
                unit: nutrient.unit,
                syncIdentifier: SyncIdentifier.make(entryID: request.entryID, nutrient: nutrient),
                syncVersion: request.syncVersion
            )
        }
    }

    /// The correlation wrapping `samples(for:authorized:)`, or `nil` when no sample can be written.
    static func correlation(for request: HealthWriteRequest, authorized: Set<Nutrient>) -> CorrelationSpec? {
        let samples = samples(for: request, authorized: authorized)
        guard !samples.isEmpty else { return nil }
        return CorrelationSpec(
            syncIdentifier: SyncIdentifier.make(mealFor: request.entryID),
            syncVersion: request.syncVersion,
            foodType: request.foodName,
            mealSlot: request.mealSlot,
            start: request.start,
            samples: samples
        )
    }
}
