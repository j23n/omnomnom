import SwiftUI

/// Environment values the app injects at launch. Defaults are safe stand-ins so
/// previews and tests render without a bundle or Health access.
extension EnvironmentValues {
    /// Search and lookup over the bundled database.
    @Entry var foodRepository: FoodRepository = FoodRepository(database: nil)

    /// The HealthKit surface behind `HealthWriting`.
    @Entry var health: any HealthWriting = UnavailableHealth()
}
