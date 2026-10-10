import AppIntents
#if FEEDBACK
import FeedbackKit
#endif
import Foundation
import os
import SwiftData
import SwiftUI

@main
struct OmnomnomApp: App {
    private let container: ModelContainer?
    private let foodRepository: FoodRepository
    /// One store serves both the write and the read surface.
    private let healthStore: HealthStore
    private let services: AppServices
    /// Where an app intent leaves what it wants shown.
    private let router: AppRouter
    #if FEEDBACK
    /// In-app feedback, in Debug builds (`FeedbackSupport`).
    @State private var feedback = FeedbackCenter.omnomnom()
    #endif

    /// Runs on the main actor during launch (`App` is main-actor isolated). Reconciliation
    /// starts here, before any scene exists, so a background Health launch registers its
    /// observer queries too; the work itself runs in a task and never blocks first paint.
    ///
    /// The app intents are given the same repository and router the views use, so a line
    /// Siri takes reaches the same composer the app shows.
    ///
    /// Everything is built into locals and assigned at the end. `add(dependency:)` takes
    /// an escaping autoclosure, so passing a property would capture `self`, which stays
    /// `inout` for the whole of a struct's initialiser. The router is a class, so the
    /// local and the property are the same object and an intent still reaches the router
    /// the views are watching.
    init() {
        let container = Self.makeContainer()
        let foodRepository = FoodRepository.bundled()
        let healthStore = HealthStore()
        let router = AppRouter()
        let services = AppServices(container: container, observing: healthStore)
        services.startReconciliationIfNeeded()
        AppDependencyManager.shared.add(dependency: foodRepository)
        AppDependencyManager.shared.add(dependency: router)
        // The store, so an intent can log without the app being open. Registered only
        // when there is one: an intent that cannot reach the store says so rather than
        // failing on a container nobody created.
        if let container { AppDependencyManager.shared.add(dependency: container) }
        self.container = container
        self.foodRepository = foodRepository
        self.healthStore = healthStore
        self.router = router
        self.services = services
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    #if FEEDBACK
                    .feedbackRedaction(feedback)
                    .environment(feedback)
                    #endif
            } else {
                StorageUnavailableView()
            }
        }
        .environment(\.foodRepository, foodRepository)
        .environment(\.health, healthStore)
        .environment(\.healthObserving, healthStore)
        .environment(\.appServices, services)
        .environment(\.appRouter, router)
    }

    /// The on-disk store, or an in-memory one when that fails. Never crashes on launch.
    private static func makeContainer() -> ModelContainer? {
        let schema = StoreSchema.schema
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            AppLog.store.error("persistent store failed, using memory: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            AppLog.store.fault("in-memory store failed too: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Shown only if neither a persistent nor an in-memory store could be created.
struct StorageUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "Storage unavailable",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("The app could not open its local store. Restart the app; if this persists, reinstall it.")
        )
    }
}
