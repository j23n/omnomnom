import Foundation

/// Which figures lead on Today.
///
/// Energy always leads and is not part of the choice. Three more sit beside it large,
/// and the rest stay in the secondary row, still always visible and never behind a tap.
///
/// The set is a width constraint and nothing more. Four large figures is what a phone
/// holds at the type sizes people actually use, and that is the only reason there is a
/// choice to make. *Which* three a person wants is not a decision this app is in a
/// position to make for them: someone watching carbohydrates and someone watching fiber
/// are both using it correctly, and a fixed set would simply be wrong for one of them.
/// Trends charts all eight regardless, because a scrolling screen has no such constraint.
nonisolated enum HeadlineNutrients {
    static let key = "headlineNutrients"

    /// How many sit beside energy.
    static let count = 3

    /// Energy, protein, carbohydrates and fat: the four spread across most of what
    /// anyone eats, and so the four a portion bucket disturbs least.
    static let standard: [Nutrient] = [.protein, .carbohydrates, .fatTotal]

    /// Everything that can be chosen, which is everything but energy.
    static var selectable: [Nutrient] {
        Nutrient.allCases.filter { $0 != .energy }
    }

    /// Stored as raw values joined by commas, since defaults hold no arrays.
    static func encode(_ nutrients: [Nutrient]) -> String {
        nutrients.map(\.rawValue).joined(separator: ",")
    }

    /// Reads a stored selection, falling back to the standard set.
    ///
    /// Unknown names are dropped and the result is padded from the standard set and
    /// capped, so a value written by a later version, or by hand, can never leave the
    /// row empty or overflowing.
    static func decode(_ raw: String) -> [Nutrient] {
        var chosen = raw
            .split(separator: ",")
            .compactMap { Nutrient(rawValue: String($0)) }
            .filter { $0 != .energy }
        var seen: Set<Nutrient> = []
        chosen = chosen.filter { seen.insert($0).inserted }
        for fallback in standard where chosen.count < count {
            if seen.insert(fallback).inserted { chosen.append(fallback) }
        }
        return Array(chosen.prefix(count))
    }

    /// The four that are not large, in the order they are published.
    static func secondary(to large: [Nutrient]) -> [Nutrient] {
        selectable.filter { !large.contains($0) }
    }
}
