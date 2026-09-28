import Foundation
import SwiftData

/// Finding the user's own recipes and foods by name or by tag.
///
/// The tag half is done in two fetches rather than one predicate: a predicate that
/// reaches through a to-many relationship is the kind of thing that works until a
/// schema changes, and a library is never large enough for the second fetch to cost
/// anything.
enum LibrarySearch {
    /// Custom foods and cached products whose name contains `text`, or that carry a tag
    /// whose name does, by name.
    static func foods(matching text: String, in context: ModelContext) throws -> [Food] {
        var found = try Food.libraryMatching(text, in: context)
        var seen = Set(found.map(\.id))
        for tag in try Tag.matching(text, in: context) {
            for food in tag.foods ?? [] where food.kind != .bundled && seen.insert(food.id).inserted {
                found.append(food)
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Recipes whose name contains `text`, or that carry a tag whose name does, by name.
    static func recipes(matching text: String, in context: ModelContext) throws -> [Recipe] {
        var found = try Recipe.matching(text, in: context)
        var seen = Set(found.map(\.id))
        for tag in try Tag.matching(text, in: context) {
            for recipe in tag.recipes ?? [] where seen.insert(recipe.id).inserted {
                found.append(recipe)
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
