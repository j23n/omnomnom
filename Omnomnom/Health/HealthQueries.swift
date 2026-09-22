import Foundation
import HealthKit

/// Query descriptors for the read side and the mapping from HealthKit samples to the
/// app's value types. Used only by `HealthStore`; nonisolated like `HealthObjects`.
nonisolated enum HealthQueries {
    /// Objects per page of an anchored read, so a first read over a large store stays bounded.
    static let pageSize = 1000
    /// Upper bound on pages per type and run; guarantees the read loop ends.
    static let maximumPages = 100

    static func anchoredDescriptor(for nutrient: Nutrient, anchor: HKQueryAnchor?) -> HKAnchoredObjectQueryDescriptor<HKQuantitySample> {
        HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: HealthObjects.quantityType(for: nutrient))],
            anchor: anchor,
            limit: pageSize
        )
    }

    static func anchoredCorrelationDescriptor(anchor: HKQueryAnchor?) -> HKAnchoredObjectQueryDescriptor<HKCorrelation> {
        HKAnchoredObjectQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food))],
            anchor: anchor,
            limit: pageSize
        )
    }

    /// One query over the given nutrient types plus the food correlation type, matching
    /// any object whose sync identifier is in `syncIdentifiers`; the delete path uses it.
    static func lookupDescriptor(nutrients: Set<Nutrient>, syncIdentifiers: [String]) -> HKSampleQueryDescriptor<HKSample> {
        let bySyncIdentifier = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: syncIdentifiers
        )
        var predicates: [HKSamplePredicate<HKSample>] = Nutrient.allCases
            .filter(nutrients.contains)
            .map { HKSamplePredicate.sample(type: HealthObjects.quantityType(for: $0), predicate: bySyncIdentifier) }
        predicates.append(HKSamplePredicate.sample(type: HKCorrelationType(.food), predicate: bySyncIdentifier))
        return HKSampleQueryDescriptor<HKSample>(predicates: predicates, sortDescriptors: [])
    }

    /// Every dietary quantity sample starting in `interval`, oldest first.
    static func daySamplesDescriptor(in interval: DateInterval) -> HKSampleQueryDescriptor<HKQuantitySample> {
        let inInterval = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let predicates = Nutrient.allCases.map { nutrient in
            HKSamplePredicate.quantitySample(type: HealthObjects.quantityType(for: nutrient), predicate: inInterval)
        }
        let byStart = SortDescriptor<HKQuantitySample>(\.startDate)
        return HKSampleQueryDescriptor<HKQuantitySample>(predicates: predicates, sortDescriptors: [byStart])
    }

    /// The sync identifier in an object's or deleted object's metadata, if it has one.
    static func syncIdentifier(in metadata: [String: Any]?) -> String? {
        metadata?[HKMetadataKeySyncIdentifier] as? String
    }

    /// The value type for one sample, or `nil` for a quantity type this app does not record.
    static func nutritionSample(from sample: HKQuantitySample, ownBundleIdentifier: String?) -> HealthNutritionSample? {
        guard let nutrient = Nutrient(healthIdentifier: sample.quantityType.identifier) else { return nil }
        let source = sample.sourceRevision.source
        return HealthNutritionSample(
            nutrient: nutrient,
            value: sample.quantity.doubleValue(for: HealthObjects.unit(for: nutrient.unit)),
            start: sample.startDate,
            isOwnBundle: source.bundleIdentifier == ownBundleIdentifier,
            sourceName: source.name,
            syncIdentifier: syncIdentifier(in: sample.metadata),
            foodType: sample.metadata?[HKMetadataKeyFoodType] as? String
        )
    }
}
