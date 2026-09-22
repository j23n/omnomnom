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

    /// Runs on the main actor during launch (`App` is main-actor isolated). Reconciliation
    /// starts here, before any scene exists, so a background Health launch registers its
    /// observer queries too; the work itself runs in a task and never blocks first paint.
    init() {
        container = Self.makeContainer()
        foodRepository = FoodRepository.bundled()
        healthStore = HealthStore()
        services = AppServices(container: container, observing: healthStore)
        services.startReconciliationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
            } else {
                StorageUnavailableView()
            }
        }
        .environment(\.foodRepository, foodRepository)
        .environment(\.health, healthStore)
        .environment(\.healthObserving, healthStore)
        .environment(\.appServices, services)
    }

    /// The on-disk store, or an in-memory one when that fails. Never crashes on launch.
    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([Food.self, LogEntry.self, Recipe.self, RecipeIngredient.self, Photo.self])
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
