#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Everything the app injects at launch, with preview stand-ins: a seeded in-memory
/// store, the bundled database when it is present, a Health fake and app services
/// without a store, so nothing reconciles. `defaults` backs every `@AppStorage`.
struct PreviewEnvironment: ViewModifier {
    let container: ModelContainer
    let health: PreviewHealth
    let repository: FoodRepository
    let services: AppServices
    let defaults: UserDefaults

    func body(content: Content) -> some View {
        content
            .modelContainer(container)
            .environment(\.foodRepository, repository)
            .environment(\.health, health)
            .environment(\.healthObserving, health)
            .environment(\.appServices, services)
            .defaultAppStorage(defaults)
    }
}

extension View {
    /// Seeds a fresh container and applies the preview environment. Health is quiet by
    /// default; pass `PreviewHealth()` to see the samples other apps wrote.
    func previewEnvironment(
        seed: PreviewSeed = .typicalDay,
        health: PreviewHealth = .quiet,
        defaults: UserDefaults = PreviewDefaults.make()
    ) -> some View {
        previewEnvironment(container: PreviewStore.container(seed: seed), health: health, defaults: defaults)
    }

    /// The preview environment around a container the preview built itself, so it can
    /// fetch rows from it first.
    func previewEnvironment(
        container: ModelContainer,
        health: PreviewHealth = .quiet,
        defaults: UserDefaults = PreviewDefaults.make()
    ) -> some View {
        modifier(PreviewEnvironment(
            container: container,
            health: health,
            repository: PreviewRepository.make(),
            services: AppServices(container: nil, observing: health, defaults: defaults),
            defaults: defaults
        ))
    }
}

/// `UserDefaults` suites for `@AppStorage` in previews, one per combination of flags,
/// so an onboarding preview and a main-tabs preview in the same canvas never share.
nonisolated enum PreviewDefaults {
    static func make(onboardingComplete: Bool = true, barcode: Bool = false, estimation: Bool = false) -> UserDefaults {
        let name = "com.johanneswindelen.omnomnom.preview.onboarding\(onboardingComplete).barcode\(barcode).estimation\(estimation)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.set(onboardingComplete, forKey: AppServices.onboardingKey)
        defaults.set(barcode, forKey: BarcodeModule.enabledKey)
        defaults.set(estimation, forKey: EstimationModule.enabledKey)
        return defaults
    }

    /// Both opt-in modules switched on.
    static var modulesOn: UserDefaults {
        make(barcode: true, estimation: true)
    }

    /// Fresh install: onboarding not done.
    static var onboardingPending: UserDefaults {
        make(onboardingComplete: false)
    }
}
#endif
