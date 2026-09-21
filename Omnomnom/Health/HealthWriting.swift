import Foundation

/// The app's whole HealthKit surface, in value types. `HealthStore` is the real
/// implementation; tests and previews use a fake. No `HK` type appears here.
nonisolated protocol HealthWriting: Sendable {
    /// `HKHealthStore.isHealthDataAvailable()`. False in previews and on unsupported devices.
    var isAvailable: Bool { get }

    /// Shows the system permission sheet for the eight dietary types (once per type).
    func requestAuthorization() async throws

    /// Nutrients whose type is currently authorized for writing. Read status is never reported by iOS.
    func authorizedNutrients() async -> Set<Nutrient>

    /// Writes one food correlation with a sample per authorized, present nutrient.
    /// Returns the nutrients actually written; empty when nothing was authorized.
    func write(_ request: HealthWriteRequest) async throws -> Set<Nutrient>

    /// Deletes the samples for `nutrients` and the correlation of one entry, in one batch.
    /// Throws `HealthWriteError.authorizationDenied` when Health no longer lets the app delete.
    func delete(entryID: UUID, nutrients: Set<Nutrient>) async throws
}

/// Everything `HealthStore` needs to build the samples for one entry.
nonisolated struct HealthWriteRequest: Hashable, Sendable {
    let entryID: UUID
    let foodName: String
    let mealSlot: MealSlot
    let start: Date
    let nutrition: Nutrition
    let syncVersion: Int
}

/// Failures the app distinguishes; anything else from HealthKit is rethrown as is.
nonisolated enum HealthWriteError: Error, Equatable, Sendable, LocalizedError {
    /// The user revoked write access, so Health refuses to delete what this app saved.
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: "Health no longer lets this app change its data."
        }
    }
}
