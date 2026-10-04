import AppIntents
import Foundation

/// One bundled food as the system sees it.
///
/// Visual intelligence shows these in its own results view, outside the app and
/// possibly long after the search ran, so the entity carries the text it will be drawn
/// with rather than a reference to look up later.
nonisolated struct FoodEntity: AppEntity, Sendable {
    /// The bundled database's own row id, which is stable for a given build of it.
    let id: Int
    let name: String
    let category: String?
    /// Kilocalories per 100 g. The bundled tables are per 100 g throughout.
    let energy: Double?

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Food",
        numericFormat: "\(placeholder: .int) foods"
    )

    static let defaultQuery = FoodEntityQuery()

    /// Title, one line of provenance and figures, and a symbol. No photograph: the
    /// bundled tables carry none, and the app never fetches one.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "carrot", isTemplate: true)
        )
    }

    /// "Fruits and Fruit Juices · 52 kcal per 100 g", or whichever half is known.
    private var subtitle: String {
        var parts: [String] = []
        if let category {
            parts.append(category)
        }
        if let energy {
            parts.append("\(Formatters.amount(energy, unit: .kilocalorie)) \(FoodMeasure.mass.referenceText)")
        }
        return parts.joined(separator: " · ")
    }

    init(_ food: BundledFood) {
        id = food.id
        name = food.name
        category = food.category
        energy = food.per100g.energy
    }
}

/// How the system looks a food up again, by the id it was handed earlier.
///
/// The bundled database ships inside the app and is replaced wholesale by an update,
/// so an id the system remembers across one of those may no longer exist. That reads
/// as no result rather than as a failure.
///
/// Not `nonisolated`, unlike the entity it returns: `@Dependency` is a property
/// wrapper and therefore a mutable stored property, which cannot be nonisolated. So the
/// query takes the target's main-actor default and reaches the database through an
/// `await`, which is where the work happens anyway.
struct FoodEntityQuery: EntityQuery {
    @Dependency private var repository: FoodRepository

    func entities(for identifiers: [Int]) async throws -> [FoodEntity] {
        var found: [FoodEntity] = []
        for id in identifiers {
            if let food = try await repository.food(id: id) {
                found.append(FoodEntity(food))
            }
        }
        return found
    }
}
