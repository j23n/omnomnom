#if DEBUG
import Foundation

/// A Health surface for previews: reports the configured authorization, "writes" by
/// returning what is authorized, never changes anything and answers day reads with a
/// fixed list of samples. Never touches HealthKit.
nonisolated struct PreviewHealth: HealthWriting, HealthObserving {
    /// `HKHealthStore.isHealthDataAvailable()` as the preview wants it.
    var isAvailable = true
    /// Nutrients whose type reads as authorized for writing.
    var authorized: Set<Nutrient> = Set(Nutrient.allCases)
    /// What `samples(in:)` returns for any interval.
    var foreignSamples: [HealthNutritionSample] = PreviewHealth.defaultForeignSamples

    init(
        isAvailable: Bool = true,
        authorized: Set<Nutrient> = Set(Nutrient.allCases),
        foreignSamples: [HealthNutritionSample] = PreviewHealth.defaultForeignSamples
    ) {
        self.isAvailable = isAvailable
        self.authorized = authorized
        self.foreignSamples = foreignSamples
    }

    /// Everything authorized, nothing else in Health.
    static let quiet = PreviewHealth(foreignSamples: [])

    /// Only the four primary nutrients may be written.
    static let partial = PreviewHealth(authorized: [.energy, .protein, .carbohydrates, .fatTotal], foreignSamples: [])

    /// Health is present but nothing may be written.
    static let denied = PreviewHealth(authorized: [], foreignSamples: [])

    /// No Health on this device.
    static let unavailable = PreviewHealth(isAvailable: false, authorized: [], foreignSamples: [])

    /// A latte from another app at 10:30, and one sample this app's bundle wrote
    /// without a matching local entry, which Today labels "not in this log".
    static let defaultForeignSamples: [HealthNutritionSample] = {
        let calendar = Calendar.current
        let latteTime = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: Date.now) ?? Date.now
        let toastTime = calendar.date(bySettingHour: 7, minute: 45, second: 0, of: Date.now) ?? Date.now
        return [
            HealthNutritionSample(
                nutrient: .energy, value: 180, start: latteTime, isOwnBundle: false,
                sourceName: "Other App", syncIdentifier: nil, foodType: "Latte"
            ),
            HealthNutritionSample(
                nutrient: .protein, value: 9.4, start: latteTime, isOwnBundle: false,
                sourceName: "Other App", syncIdentifier: nil, foodType: "Latte"
            ),
            HealthNutritionSample(
                nutrient: .energy, value: 210, start: toastTime, isOwnBundle: true,
                sourceName: "Omnomnom", syncIdentifier: SyncIdentifier.make(entryID: UUID(), nutrient: .energy),
                foodType: "Toast with butter"
            ),
        ]
    }()

    func requestAuthorization() async throws {}

    func authorizedNutrients() async -> Set<Nutrient> {
        authorized
    }

    /// What the real store would write: the authorized nutrients the entry has values for.
    func write(_ request: HealthWriteRequest) async throws -> Set<Nutrient> {
        authorized.intersection(request.nutrition.presentNutrients)
    }

    func delete(entryID: UUID, nutrients: Set<Nutrient>) async throws {}

    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {}

    func changes(since anchors: HealthAnchors) async throws -> HealthChanges {
        .unchanged(anchors: anchors)
    }

    func samples(in interval: DateInterval) async throws -> [HealthNutritionSample] {
        foreignSamples
    }
}
#endif
