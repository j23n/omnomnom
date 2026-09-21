import Foundation

/// A household measure for a bundled food, such as "1 medium" at 182 g.
nonisolated struct Portion: Hashable, Sendable {
    let label: String
    let grams: Double
}
