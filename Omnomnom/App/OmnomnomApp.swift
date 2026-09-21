import Foundation
import os
import SwiftData
import SwiftUI

@main
struct OmnomnomApp: App {
    private let container: ModelContainer?
    private let foodRepository: FoodRepository
    private let health: any HealthWriting

    init() {
        container = Self.makeContainer()
        foodRepository = FoodRepository.bundled()
        health = HealthStore()
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
        .environment(\.health, health)
    }

    /// The on-disk store, or an in-memory one when that fails. Never crashes on launch.
    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([Food.self, LogEntry.self])
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
