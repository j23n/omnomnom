import Foundation

/// Nutrient amounts, either per 100 units of a food — grams or millilitres, as the
/// food's `FoodMeasure` says — or absolute (a logged entry or a total).
///
/// A missing nutrient is `nil`, never 0, mirroring the bundled database where FDC
/// simply has no value. Energy is always present for bundled foods but is optional
/// here so the type stays honest for totals of an empty day.
nonisolated struct Nutrition: Codable, Hashable, Sendable {
    var energy: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fatTotal: Double?
    var fatSaturated: Double?
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?

    init(
        energy: Double? = nil,
        protein: Double? = nil,
        carbohydrates: Double? = nil,
        fatTotal: Double? = nil,
        fatSaturated: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil
    ) {
        self.energy = energy
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fatTotal = fatTotal
        self.fatSaturated = fatSaturated
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
    }

    /// Nothing known: every nutrient is `nil`. The identity element for `+`.
    static let empty = Nutrition()

    /// Every nutrient is 0. Use as the seed when summing a day so an empty day reads 0, not blank.
    static let zero = Nutrition(
        energy: 0, protein: 0, carbohydrates: 0, fatTotal: 0,
        fatSaturated: 0, fiber: 0, sugar: 0, sodium: 0
    )

    subscript(nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .energy: energy
            case .protein: protein
            case .carbohydrates: carbohydrates
            case .fatTotal: fatTotal
            case .fatSaturated: fatSaturated
            case .fiber: fiber
            case .sugar: sugar
            case .sodium: sodium
            }
        }
        set {
            switch nutrient {
            case .energy: energy = newValue
            case .protein: protein = newValue
            case .carbohydrates: carbohydrates = newValue
            case .fatTotal: fatTotal = newValue
            case .fatSaturated: fatSaturated = newValue
            case .fiber: fiber = newValue
            case .sugar: sugar = newValue
            case .sodium: sodium = newValue
            }
        }
    }

    /// Nutrients that have a value.
    var presentNutrients: Set<Nutrient> {
        Set(Nutrient.allCases.filter { self[$0] != nil })
    }

    /// Treats `self` as per 100 units of the food and returns the amounts in `grams` of
    /// it. The unit is the food's own, so this scales millilitres exactly as it scales
    /// grams; nothing here converts between the two.
    func scaled(toGrams grams: Double) -> Nutrition {
        map { $0 * grams / 100 }
    }

    /// Applies `transform` to every present nutrient, leaving `nil` values `nil`.
    func map(_ transform: (Double) -> Double) -> Nutrition {
        var result = Nutrition()
        for nutrient in Nutrient.allCases {
            if let value = self[nutrient] {
                result[nutrient] = transform(value)
            }
        }
        return result
    }

    /// Per-nutrient sum. A nutrient missing on both sides stays `nil`; missing on one side counts as 0.
    static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        var result = Nutrition()
        for nutrient in Nutrient.allCases {
            switch (lhs[nutrient], rhs[nutrient]) {
            case (nil, nil): result[nutrient] = nil
            case let (a, b): result[nutrient] = (a ?? 0) + (b ?? 0)
            }
        }
        return result
    }
}
