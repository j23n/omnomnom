import Foundation
import os

/// The app's view of the bundled data: search, lookup, portions and the attribution
/// manifest. A value type wrapping the `SQLiteDatabase` actor, so it can sit in the
/// SwiftUI environment and be called from anywhere.
///
/// When the bundle lacks `foods.sqlite` (the pipeline was not run) every query
/// throws `FoodRepositoryError.databaseMissing` instead of crashing.
nonisolated struct FoodRepository: Sendable {
    let database: SQLiteDatabase?
    let sourcesURL: URL?

    init(database: SQLiteDatabase?, sourcesURL: URL? = nil) {
        self.database = database
        self.sourcesURL = sourcesURL
    }

    /// Opens the database and manifest shipped in `bundle`, logging what is missing.
    static func bundled(in bundle: Bundle = .main) -> FoodRepository {
        let sourcesURL = bundle.url(forResource: "sources", withExtension: "json")
        guard let databaseURL = bundle.url(forResource: "foods", withExtension: "sqlite") else {
            AppLog.foodDB.error("foods.sqlite is not in the bundle; run Tools/fooddb before building")
            return FoodRepository(database: nil, sourcesURL: sourcesURL)
        }
        do {
            let database = try SQLiteDatabase(url: databaseURL)
            return FoodRepository(database: database, sourcesURL: sourcesURL)
        } catch {
            AppLog.foodDB.error("cannot open foods.sqlite: \(error.localizedDescription, privacy: .private)")
            return FoodRepository(database: nil, sourcesURL: sourcesURL)
        }
    }

    func search(_ text: String) async throws -> [BundledFood] {
        try await open().search(text)
    }

    func food(id: Int) async throws -> BundledFood? {
        try await open().food(id: id)
    }

    func portions(for foodID: Int) async throws -> [Portion] {
        try await open().portions(forFoodID: foodID)
    }

    /// Number of foods in the bundle, from `meta.food_count`.
    func foodCount() async throws -> Int {
        let raw = try await open().metaValue(forKey: "food_count") ?? "0"
        return Int(raw) ?? 0
    }

    /// The attribution manifest written by the pipeline next to the database.
    func sources() throws -> [SourceManifest] {
        guard let sourcesURL else { throw FoodRepositoryError.sourcesMissing }
        let data = try Data(contentsOf: sourcesURL)
        return try JSONDecoder().decode([SourceManifest].self, from: data)
    }

    private func open() throws -> SQLiteDatabase {
        guard let database else { throw FoodRepositoryError.databaseMissing }
        return database
    }
}

nonisolated enum FoodRepositoryError: Error, Sendable, LocalizedError {
    case databaseMissing
    case sourcesMissing

    var errorDescription: String? {
        switch self {
        case .databaseMissing: "The bundled food database is missing. Run Tools/fooddb before building."
        case .sourcesMissing: "sources.json is missing from the app bundle."
        }
    }
}
