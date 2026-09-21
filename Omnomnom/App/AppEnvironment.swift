import SwiftUI

/// Environment values the app injects at launch. Defaults are safe stand-ins so
/// previews and tests render without a bundle or Health access.
extension EnvironmentValues {
    /// Search and lookup over the bundled database.
    @Entry var foodRepository: FoodRepository = FoodRepository(database: nil)

    /// The HealthKit write surface behind `HealthWriting`.
    @Entry var health: any HealthWriting = UnavailableHealth()

    /// The HealthKit read surface behind `HealthObserving`; the same store as `health`.
    @Entry var healthObserving: any HealthObserving = UnavailableHealth()

    /// Launch-time services; the default has no store and never reconciles.
    @Entry var appServices: AppServices = AppServices(container: nil, observing: UnavailableHealth())
}
