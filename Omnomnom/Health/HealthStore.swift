import Foundation
import HealthKit
import os

/// The only place HealthKit types exist. Every method takes and returns the app's
/// own value types; `HKHealthStore` and the objects built for it never leave the actor.
actor HealthStore: HealthWriting {
    private let store = HKHealthStore()

    nonisolated let isAvailable: Bool = HKHealthStore.isHealthDataAvailable()

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let share = Set<HKSampleType>(Nutrient.allCases.map { HealthObjects.quantityType(for: $0) })
        let read = Set<HKObjectType>(Nutrient.allCases.map { HealthObjects.quantityType(for: $0) })
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            AppLog.health.info("authorization sheet completed")
        } catch {
            AppLog.health.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func authorizedNutrients() async -> Set<Nutrient> {
        guard isAvailable else { return [] }
        return Set(Nutrient.allCases.filter {
            store.authorizationStatus(for: HealthObjects.quantityType(for: $0)) == .sharingAuthorized
        })
    }

    func write(_ request: HealthWriteRequest) async throws -> Set<Nutrient> {
        guard isAvailable else { return [] }
        let authorized = await authorizedNutrients()
        guard let spec = HealthSampleBuilder.correlation(for: request, authorized: authorized) else {
            AppLog.health.notice("nothing authorized; entry \(request.entryID.uuidString, privacy: .public) stays local")
            return []
        }
        let correlation = HealthObjects.makeCorrelation(spec)
        do {
            try await store.save(correlation)
        } catch {
            AppLog.health.error("save failed for \(request.entryID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let written = Set(spec.samples.map(\.nutrient))
        AppLog.health.info("wrote \(written.count) samples for \(request.entryID.uuidString, privacy: .public)")
        return written
    }

    /// Finds every object carrying one of the entry's sync identifiers (samples and the
    /// correlation, since deleting a correlation leaves its samples behind) and deletes
    /// them in one all-or-nothing batch.
    func delete(entryID: UUID, nutrients: Set<Nutrient>) async throws {
        guard isAvailable else { return }
        let identifiers = HealthSampleBuilder.syncIdentifiers(entryID: entryID, nutrients: nutrients)
        guard !identifiers.isEmpty else { return }
        let descriptor = HealthObjects.lookupDescriptor(nutrients: nutrients, syncIdentifiers: identifiers)
        do {
            let objects = try await descriptor.result(for: store)
            guard !objects.isEmpty else {
                AppLog.health.notice("nothing to delete for \(entryID.uuidString, privacy: .public)")
                return
            }
            try await store.delete(objects)
            AppLog.health.info("deleted \(objects.count) objects for \(entryID.uuidString, privacy: .public)")
        } catch let error as HKError where error.code == .errorAuthorizationDenied {
            AppLog.health.error("delete refused for \(entryID.uuidString, privacy: .public): authorization denied")
            throw HealthWriteError.authorizationDenied
        } catch {
            AppLog.health.error("delete failed for \(entryID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
