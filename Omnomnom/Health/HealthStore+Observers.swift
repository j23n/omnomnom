import Foundation
import HealthKit
import os

/// Observer registration for `HealthStore`; the `HealthObserving` conformance lives in
/// `HealthStore+Observing`, this witness just sits in its own file.
extension HealthStore {
    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {
        guard isAvailable, observerQueries.isEmpty else { return }
        for nutrient in Nutrient.allCases {
            let type = HealthObjects.quantityType(for: nutrient)
            let identifier = type.identifier
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if let error {
                    AppLog.health.error("observer for \(identifier, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
                }
                // HealthKit's completion block is not Sendable. It must be called exactly once,
                // from any thread, after the change was handled; that is all the task does with it.
                nonisolated(unsafe) let done = completion
                Task {
                    await onChange()
                    done()
                }
            }
            store.execute(query)
            observerQueries.append(query)
        }
        AppLog.health.info("observing \(self.observerQueries.count) types")
        var firstFailure: (any Error)?
        for nutrient in Nutrient.allCases {
            do {
                try await store.enableBackgroundDelivery(for: HealthObjects.quantityType(for: nutrient), frequency: .immediate)
            } catch {
                AppLog.health.error("background delivery for \(nutrient.rawValue, privacy: .public) refused: \(error.localizedDescription, privacy: .public)")
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure { throw firstFailure }
    }
}
