import Foundation

/// Read-only access to the bundled `foods.sqlite`, off the main actor.
///
/// Three cached statements: FTS5 search, food by id, portions by food id.
/// Everything crossing the actor boundary is a `Sendable` value type;
/// the `OpaquePointer`s stay inside `SQLiteConnection`.
actor SQLiteDatabase {
    private let connection: SQLiteConnection

    private static let foodColumns = """
        f.id, f.name, f.category, f.kcal_100g, f.protein_100g, f.carb_100g, f.fat_100g, \
        f.satfat_100g, f.fiber_100g, f.sugar_100g, f.sodium_mg_100g, f.popularity
        """

    private static let searchSQL = """
        SELECT \(foodColumns) FROM foods_fts JOIN foods f ON f.id = foods_fts.rowid \
        WHERE foods_fts MATCH ?1 ORDER BY bm25(foods_fts) - (f.popularity * 0.1) LIMIT 50
        """

    private static let foodByIDSQL = "SELECT \(foodColumns) FROM foods f WHERE f.id = ?1"

    private static let portionsSQL = "SELECT label, grams FROM portions WHERE food_id = ?1 ORDER BY seq"

    private static let metaSQL = "SELECT value FROM meta WHERE key = ?1"

    /// Opens the database at `url`. Throws `SQLiteError.open` when the file cannot be opened.
    init(url: URL) throws {
        connection = try SQLiteConnection(url: url)
    }

    /// Runs an FTS5 MATCH built by `FoodQuery`. Empty input yields no rows.
    func search(_ text: String) throws -> [BundledFood] {
        guard let expression = FoodQuery.ftsMatchExpression(for: text) else { return [] }
        let statement = try connection.statement(for: Self.searchSQL)
        try connection.bind(expression, to: 1, in: statement)
        var foods: [BundledFood] = []
        while try connection.step(statement) {
            foods.append(readFood(statement))
        }
        return foods
    }

    func food(id: Int) throws -> BundledFood? {
        let statement = try connection.statement(for: Self.foodByIDSQL)
        try connection.bind(id, to: 1, in: statement)
        guard try connection.step(statement) else { return nil }
        let food = readFood(statement)
        _ = try connection.step(statement)
        return food
    }

    func portions(forFoodID id: Int) throws -> [Portion] {
        let statement = try connection.statement(for: Self.portionsSQL)
        try connection.bind(id, to: 1, in: statement)
        var portions: [Portion] = []
        while try connection.step(statement) {
            let label = connection.text(statement, 0) ?? ""
            let grams = connection.double(statement, 1) ?? 0
            portions.append(Portion(label: label, grams: grams))
        }
        return portions
    }

    /// A value from the `meta` table, such as `food_count`.
    func metaValue(forKey key: String) throws -> String? {
        let statement = try connection.statement(for: Self.metaSQL)
        try connection.bind(key, to: 1, in: statement)
        guard try connection.step(statement) else { return nil }
        let value = connection.text(statement, 0)
        _ = try connection.step(statement)
        return value
    }

    private func readFood(_ statement: OpaquePointer) -> BundledFood {
        let per100g = Nutrition(
            energy: connection.double(statement, 3),
            protein: connection.double(statement, 4),
            carbohydrates: connection.double(statement, 5),
            fatTotal: connection.double(statement, 6),
            fatSaturated: connection.double(statement, 7),
            fiber: connection.double(statement, 8),
            sugar: connection.double(statement, 9),
            sodium: connection.double(statement, 10)
        )
        return BundledFood(
            id: connection.int(statement, 0),
            name: connection.text(statement, 1) ?? "",
            category: connection.text(statement, 2),
            per100g: per100g,
            popularity: connection.int(statement, 11)
        )
    }
}
