import Foundation

/// Whether a food is measured by mass or by volume: grams for a solid, millilitres for
/// a drink, a stock or an oil sold by the bottle.
///
/// The two are never converted into each other. The app does not know a food's density
/// and must not guess one, so a food's nutrition is per 100 of its own unit, an amount
/// is in that same unit, and the arithmetic stays unit-agnostic: "per 100 units times N
/// units" holds either way. Only the labels and the totals tell the difference.
nonisolated enum FoodMeasure: String, CaseIterable, Codable, Sendable {
    case mass
    case volume

    /// Shown after an amount: "182 g", "250 ml".
    var unitSymbol: String {
        switch self {
        case .mass: "g"
        case .volume: "ml"
        }
    }

    /// What the per-100 values are stated against: "100 g" or "100 ml".
    var referenceUnit: String {
        "100 \(unitSymbol)"
    }

    /// "per 100 g" or "per 100 ml", for the captions that name the reference.
    var referenceText: String {
        "per \(referenceUnit)"
    }

    /// The unit's name for VoiceOver, which would otherwise spell out the symbol.
    var spokenName: String {
        switch self {
        case .mass: "grams"
        case .volume: "millilitres"
        }
    }

    /// The unit as the food editor's picker and the amount field name it.
    var displayName: String {
        switch self {
        case .mass: "Grams"
        case .volume: "Millilitres"
        }
    }
}
