import Foundation

/// One row of the bundled `foods` table.
nonisolated struct BundledFood: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let category: String?
    let per100g: Nutrition
    let popularity: Int
}
