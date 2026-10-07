import Foundation
import SwiftData

/// One row of the search results, whatever it came from.
///
/// Two groups, not five. What the user owns comes first, ordered by what they last
/// ate, because that is almost always the answer. Below it the bundled tables and Open
/// Food Facts are read as one list ordered by `SearchRelevance`, where a pill per row
/// says which of the two a figure came from — a question that only arises down there.
nonisolated struct SearchResult: Identifiable, Hashable, Sendable {
    /// Where a row's numbers come from, which is what the pill says.
    nonisolated enum Provenance: Hashable, Sendable {
        /// Built by the user out of other foods.
        case recipe
        /// Typed by the user, or corrected by them.
        case yours
        /// A measured row of the bundled tables.
        case database
        /// Crowdsourced, whether already saved here or still out on the network.
        case openFoodFacts

        var pill: String {
            switch self {
            case .recipe: "Recipe"
            case .yours: "Yours"
            case .database: "Database"
            case .openFoodFacts: "Open Food Facts"
            }
        }
    }

    /// What tapping the row does. A product found by name has no values yet, so it is
    /// fetched by its barcode first; everything else is ready to log.
    nonisolated enum Action: Hashable, Sendable {
        case choice(FoodChoice)
        case fetch(ProductRecord)
    }

    /// Which of the eight nutrient figures a row actually carries.
    ///
    /// The one thing that tells two otherwise identical rows apart. Two cheeses with the
    /// same name and the same energy are not the same row if one of them has no figure for
    /// fibre: everything summed over it afterwards is a floor rather than a total, and the
    /// person choosing is the only one who can prefer the fuller row.
    ///
    /// A count and never a grade. "Six of eight" is a fact about a record; it says nothing
    /// about the food, and a row short of a figure is often the right answer anyway —
    /// a brand that only declares what a label has to declare is still that brand.
    nonisolated struct Figures: Hashable, Sendable {
        /// Nutrients with no value at all.
        let missing: Set<Nutrient>

        var isComplete: Bool { missing.isEmpty }

        init(missing: Set<Nutrient>) {
            self.missing = missing
        }

        init(of nutrition: Nutrition) {
            self.init(missing: nutrition.missingNutrients)
        }

        /// "All 8", "No fibre figure", "3 figures missing": what the pill says.
        ///
        /// The gap is named where there is one of it, because which figure is missing is
        /// what decides whether this row will do — someone watching sodium cares about a
        /// different absence than someone watching fibre. Past one, the count is the only
        /// thing that fits.
        var pill: String {
            switch missing.count {
            case 0: "All \(Nutrient.allCases.count)"
            case 1: "No \(names(of: missing)) figure"
            default: "\(missing.count) figures missing"
            }
        }

        /// The same, spelled out, for a screen reader: a pill is read in a list of pills
        /// and "All 8" on its own says nothing about what eight.
        var spoken: String {
            switch missing.count {
            case 0: "Every nutrient figure"
            case 1: "No figure for \(names(of: missing))"
            default: "Missing \(missing.count) nutrient figures: \(names(of: missing))"
            }
        }

        /// In the nutrients' own display order, never in order of how much is missing,
        /// which would be a judgement about which gap matters.
        private func names(of nutrients: Set<Nutrient>) -> String {
            Nutrient.allCases
                .filter { nutrients.contains($0) }
                .map { $0.displayName.lowercased() }
                .formatted(.list(type: .and))
        }
    }

    let id: String
    let provenance: Provenance
    let name: String
    /// The one line under the name, already composed; never repeats the pill.
    let caption: String
    /// Which of the eight figures this row holds.
    let figures: Figures
    let photo: Data?
    let rank: Double
    /// When the user last logged this, which orders their own matches; `nil` for a row
    /// they have never eaten and for anything that is not theirs.
    let lastUsed: Date?
    let action: Action
}

// MARK: - Building rows from the Library

@MainActor
extension SearchResult {
    static func make(recipe: Recipe, query: String) -> SearchResult {
        let choice = recipe.choice
        return SearchResult(
            id: "recipe-\(recipe.id.uuidString)",
            provenance: .recipe,
            name: choice.name,
            caption: caption(for: choice),
            figures: Figures(of: choice.perUnit),
            photo: choice.photo,
            rank: SearchRelevance.rank(
                anyOf: [choice.name] + (recipe.tags ?? []).map(\.name),
                query: query,
                bonus: 0
            ),
            lastUsed: recipe.lastUsed,
            action: .choice(choice)
        )
    }

    /// `nil` for a food that cannot be turned into a choice, which is a bundled row
    /// the Library holds only to remember an amount by.
    static func make(food: Food, query: String) -> SearchResult? {
        guard let choice = food.choice else { return nil }
        let crowdsourced = food.source == .openFoodFacts
        return SearchResult(
            id: "food-\(food.id.uuidString)",
            provenance: crowdsourced ? .openFoodFacts : .yours,
            name: choice.name,
            caption: caption(for: choice),
            figures: Figures(of: choice.perUnit),
            photo: choice.photo,
            rank: SearchRelevance.rank(
                anyOf: [choice.name] + [choice.attribution?.brand].compactMap { $0 }
                    + (food.tags ?? []).map(\.name),
                query: query,
                bonus: 0
            ),
            lastUsed: food.lastUsed,
            action: .choice(choice)
        )
    }
}

// MARK: - Building rows from the database and the network

extension SearchResult {
    static func make(bundled food: BundledFood, query: String) -> SearchResult {
        var parts: [String] = []
        if let category = food.category {
            parts.append(category)
        }
        // The bundled tables are per 100 g throughout, so the unit is settled here.
        parts.append(
            "\(Formatters.amount(food.per100g.energy, unit: .kilocalorie)) \(FoodMeasure.mass.referenceText)"
        )
        return SearchResult(
            id: "bundled-\(food.id)",
            provenance: .database,
            name: food.name,
            caption: parts.joined(separator: " · "),
            figures: Figures(of: food.per100g),
            photo: nil,
            rank: SearchRelevance.rank(
                anyOf: [food.name], query: query,
                bonus: SearchRelevance.bonus(isCrowdsourced: false)
            ),
            lastUsed: nil,
            action: .choice(FoodChoice(bundled: food))
        )
    }

    static func make(product record: ProductRecord, query: String) -> SearchResult {
        var parts: [String] = []
        if let brand = record.brand {
            parts.append(brand)
        }
        if let energy = record.per100g.energy {
            parts.append(
                "\(Formatters.amount(energy, unit: .kilocalorie)) \(record.measure.referenceText)"
            )
        }
        return SearchResult(
            id: "product-\(record.code)",
            provenance: .openFoodFacts,
            name: record.name ?? record.code,
            caption: parts.joined(separator: " · "),
            figures: Figures(of: record.per100g),
            photo: nil,
            rank: SearchRelevance.rank(
                anyOf: [record.name, record.brand].compactMap { $0 }, query: query,
                bonus: SearchRelevance.bonus(isCrowdsourced: true)
            ),
            lastUsed: nil,
            action: .fetch(record)
        )
    }

    /// "Whole Earth · Last 30 g · 588 kcal per 100 g". Where the numbers came from is
    /// the pill's business, so it is not repeated here.
    static func caption(for choice: FoodChoice) -> String {
        var parts: [String] = []
        if let brand = choice.attribution?.brand {
            parts.append(brand)
        }
        if let last = choice.lastAmount {
            parts.append("Last \(choice.amountText(last))")
        }
        parts.append(
            "\(Formatters.amount(choice.perUnit.energy, unit: .kilocalorie)) per \(choice.unitText)"
        )
        return parts.joined(separator: " · ")
    }
}

// MARK: - Grouping

nonisolated enum SearchResults {
    /// The two groups the results are shown in.
    nonisolated struct Sections: Hashable, Sendable {
        /// The user's own recipes, foods and saved products.
        var yours: [SearchResult] = []
        /// The bundled tables and Open Food Facts, read as one list.
        var others: [SearchResult] = []

        var isEmpty: Bool {
            yours.isEmpty && others.isEmpty
        }
    }

    /// Everything found, in the two groups and the order each is shown in.
    ///
    /// A product already in the Library is dropped from the network half: it is the
    /// same product, and the saved copy knows what the user last logged of it.
    static func sections(
        local: [SearchResult], database: [SearchResult], products: [SearchResult]
    ) -> Sections {
        let saved = Set(local.compactMap(\.barcode))
        let remote = products.filter { result in
            guard let barcode = result.barcode else { return true }
            return !saved.contains(barcode)
        }
        return Sections(yours: yours(local), others: ordered(database + remote))
    }

    /// The user's own matches: what they have eaten, most recently eaten first, then
    /// everything else by how well it matches.
    ///
    /// Recency beats relevance here and that is deliberate. Type "oat" with porridge
    /// every morning and oatcakes once a year in the Library, and the better text match
    /// is the oatcakes — the shorter name — while the answer is the porridge.
    static func yours(_ results: [SearchResult]) -> [SearchResult] {
        let eaten = results
            .filter { $0.lastUsed != nil }
            .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        return eaten + ordered(results.filter { $0.lastUsed == nil })
    }

    /// Best match first; ties keep their position, which `sorted(by:)` alone does not
    /// promise.
    static func ordered(_ results: [SearchResult]) -> [SearchResult] {
        results.enumerated()
            .sorted { left, right in
                left.element.rank == right.element.rank
                    ? left.offset < right.offset
                    : left.element.rank > right.element.rank
            }
            .map(\.element)
    }
}

extension SearchResult {
    /// The barcode behind the row, saved or not, for matching one against the other.
    ///
    /// `nonisolated` because `SearchResults` groups rows off the main actor and forms a
    /// key path to this. Everything it reads is a stored value on a `Sendable` type, so
    /// the isolation the extension would otherwise inherit from the target's default is
    /// not something this property needs.
    nonisolated var barcode: String? {
        switch action {
        case .choice(let choice): choice.attribution?.barcode
        case .fetch(let record): record.code
        }
    }
}
