import Foundation
import Testing
@testable import Omnomnom

struct SQLiteDatabaseTests {
    private func openFixture() throws -> SQLiteDatabase {
        let url = try #require(Fixtures.url("foods", "sqlite"))
        return try SQLiteDatabase(url: url)
    }

    @Test func opensTheFixtureAndReadsMeta() async throws {
        let database = try openFixture()
        #expect(try await database.metaValue(forKey: "food_count") == "7")
        #expect(try await database.metaValue(forKey: "schema_version") == "1")
        #expect(try await database.metaValue(forKey: "does_not_exist") == nil)
    }

    @Test func missingFileThrowsOpenError() {
        let url = URL(fileURLWithPath: "/nonexistent/omnomnom-\(UUID().uuidString).sqlite")
        #expect(throws: SQLiteError.self) {
            _ = try SQLiteDatabase(url: url)
        }
    }

    @Test func prefixSearchFindsApples() async throws {
        let database = try openFixture()
        let results = try await database.search("appl")
        #expect(results.count == 1)
        let apple = try #require(results.first)
        #expect(apple.id == 1)
        #expect(apple.name == "Apples, raw, with skin")
        #expect(apple.category == "Fruits and Fruit Juices")
        #expect(apple.per100g.energy == 52)
        #expect(apple.per100g.sodium == 1)
        #expect(apple.popularity == 100)
    }

    @Test func multiTokenSearchRequiresEveryToken() async throws {
        let database = try openFixture()
        #expect(try await database.search("chicken breast").map(\.id) == [3])
        #expect(try await database.search("chicken banana").isEmpty)
        #expect(try await database.search("").isEmpty)
        #expect(try await database.search("zzzz").isEmpty)
    }

    @Test func searchIsRepeatableOnCachedStatement() async throws {
        let database = try openFixture()
        let first = try await database.search("raw")
        let second = try await database.search("raw")
        #expect(first == second)
        #expect(first.count == 3)
    }

    @Test func foodByIDAndMissingNutrientsAreNil() async throws {
        let database = try openFixture()
        let banana = try #require(try await database.food(id: 2))
        #expect(banana.name == "Bananas, raw")
        #expect(banana.per100g.fatSaturated == nil)
        #expect(banana.per100g.fiber == 2.6)
        let egg = try #require(try await database.food(id: 7))
        #expect(egg.category == nil)
        #expect(try await database.food(id: 999) == nil)
    }

    @Test func portionsComeInSequenceOrder() async throws {
        let database = try openFixture()
        let portions = try await database.portions(forFoodID: 1)
        #expect(portions.map(\.label) == ["1 medium (3\" dia)", "1 cup, chopped", "0.5 cup"])
        #expect(portions.map(\.grams) == [182, 125, 62.5])
        #expect(try await database.portions(forFoodID: 999).isEmpty)
    }

    @Test func repositoryReadsSourcesManifest() throws {
        let repository = FoodRepository(database: nil, sourcesURL: Fixtures.url("sources", "json"))
        let sources = try repository.sources()
        #expect(sources.count == 1)
        #expect(sources.first?.id == "fdc")
        #expect(sources.first?.licence == "CC0 1.0")
        #expect(sources.first?.datasets.map(\.id) == ["fdc_foundation", "fdc_sr_legacy"])
        #expect(sources.first?.licenceURL == "https://creativecommons.org/publicdomain/zero/1.0/")
    }

    @Test func repositoryWithoutDatabaseThrowsInsteadOfCrashing() async {
        let repository = FoodRepository(database: nil)
        await #expect(throws: FoodRepositoryError.self) {
            _ = try await repository.search("apple")
        }
    }
}
