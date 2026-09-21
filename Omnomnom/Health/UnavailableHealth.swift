import Foundation

/// Stand-in used as the environment default and in previews: Health is absent, nothing
/// is written, nothing changes and nothing is read.
nonisolated struct UnavailableHealth: HealthWriting, HealthObserving {
    let isAvailable = false

    func requestAuthorization() async throws {}

    func authorizedNutrients() async -> Set<Nutrient> { [] }

    func write(_ request: HealthWriteRequest) async throws -> Set<Nutrient> { [] }

    func delete(entryID: UUID, nutrients: Set<Nutrient>) async throws {}

    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {}

    func changes(since anchors: HealthAnchors) async throws -> HealthChanges { .unchanged(anchors: anchors) }

    func samples(in interval: DateInterval) async throws -> [HealthNutritionSample] { [] }
}
