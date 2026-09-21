import Foundation
import HealthKit

/// Pure constructors for HealthKit objects and queries, used only by `HealthStore`.
/// Nonisolated so every value they return starts in a fresh region.
nonisolated enum HealthObjects {
    static func quantityType(for nutrient: Nutrient) -> HKQuantityType {
        HKQuantityType(HKQuantityTypeIdentifier(rawValue: nutrient.healthIdentifier))
    }

    static func unit(for unit: NutrientUnit) -> HKUnit {
        switch unit {
        case .kilocalorie: .kilocalorie()
        case .gram: .gram()
        case .milligram: .gramUnit(with: .milli)
        }
    }

    static func makeSample(_ spec: SampleSpec, at date: Date) -> HKQuantitySample {
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: spec.syncIdentifier,
            HKMetadataKeySyncVersion: NSNumber(value: spec.syncVersion),
        ]
        return HKQuantitySample(
            type: quantityType(for: spec.nutrient),
            quantity: HKQuantity(unit: unit(for: spec.unit), doubleValue: spec.value),
            start: date,
            end: date,
            metadata: metadata
        )
    }

    /// Saving the correlation saves the contained samples with it.
    static func makeCorrelation(_ spec: CorrelationSpec) -> HKCorrelation {
        var objects = Set<HKSample>()
        for sample in spec.samples {
            objects.insert(makeSample(sample, at: spec.start))
        }
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: spec.syncIdentifier,
            HKMetadataKeySyncVersion: NSNumber(value: spec.syncVersion),
            HKMetadataKeyFoodType: spec.foodType,
            HealthSampleBuilder.mealSlotMetadataKey: spec.mealSlot.rawValue,
        ]
        return HKCorrelation(
            type: HKCorrelationType(.food),
            start: spec.start,
            end: spec.start,
            objects: objects,
            metadata: metadata
        )
    }
}
