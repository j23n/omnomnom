import Foundation

/// One product as Open Food Facts describes it, reduced to what the app keeps: the
/// code, a name, the first brand, whether the label counts the product by mass or by
/// volume, and the eight nutrients per 100 of that unit.
///
/// Decoding is lenient because the API is: nutriment values arrive as numbers or as
/// strings, energy may exist only in kilojoules, and sodium may exist only as salt.
/// Nothing beyond the eight nutrients is read, and images are never requested.
nonisolated struct ProductRecord: Hashable, Sendable, Decodable {
    let code: String
    /// `product_name`, trimmed and capped at `maximumTextLength`; `nil` when missing or blank.
    let name: String?
    /// The first entry of the comma-separated `brands`, trimmed and capped likewise.
    let brand: String?
    /// What the label's own quantity is counted in. Open Food Facts states the
    /// nutriments per 100 g or per 100 ml to match it, under the same `_100g` keys.
    let measure: FoodMeasure

    /// Longest name or brand kept; upstream text is community-edited and unbounded.
    static let maximumTextLength = 200
    let per100g: Nutrition

    /// A record without energy cannot be logged, so the flow falls back to manual entry.
    var isUsable: Bool {
        per100g.energy != nil
    }

    init(code: String, name: String?, brand: String?, per100g: Nutrition, measure: FoodMeasure = .mass) {
        self.code = code
        self.name = name
        self.brand = brand
        self.per100g = per100g
        self.measure = measure
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case nutriments
        case quantity
        case quantityUnit = "product_quantity_unit"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .productName))
        let brands = try container.decodeIfPresent(String.self, forKey: .brands) ?? ""
        brand = Self.trimmed(brands.split(separator: ",", maxSplits: 1).first.map(String.init))
        per100g = try container.decodeIfPresent(Nutriments.self, forKey: .nutriments)?.per100g ?? .empty
        // Either field may arrive as a number rather than a string; a value that is not
        // text says nothing about the unit, so it reads as absent.
        measure = Self.inferredMeasure(
            quantityUnit: try? container.decodeIfPresent(String.self, forKey: .quantityUnit),
            quantity: try? container.decodeIfPresent(String.self, forKey: .quantity)
        )
    }

    /// Unit names that mean the label counts a volume. Anything else, including a
    /// missing field, means mass: guessing volume from a bare number would be a guess
    /// at the density, which this app never makes.
    private static let volumeUnits: Set<String> = ["ml", "cl", "dl", "l", "litre", "litres", "liter", "liters"]

    /// Whether a product is measured by volume, from `product_quantity_unit` and, since
    /// that field is often missing, the free-text `quantity` on the label: "1 l",
    /// "330ml" and "6 x 25 cl" all name a volume. Only the unit is read, never the figure.
    static func inferredMeasure(quantityUnit: String?, quantity: String?) -> FoodMeasure {
        for text in [quantityUnit, quantity] {
            guard let text else { continue }
            // Split on everything that is not a letter, so "330ml" yields "ml" while a
            // word that merely contains a unit letter, such as "gel", yields no match.
            let words = text.lowercased().split(whereSeparator: { !$0.isLetter })
            if words.contains(where: { volumeUnits.contains(String($0)) }) { return .volume }
        }
        return .mass
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(maximumTextLength))
    }
}

/// The envelope of `GET /api/v2/product/{code}.json`. `status` 1 means the product
/// exists; anything else, or a missing product, is a miss rather than an error.
nonisolated struct ProductResponse: Sendable, Decodable {
    let isFound: Bool
    let product: ProductRecord?

    private enum CodingKeys: String, CodingKey {
        case status
        case product
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFound = try container.decodeIfPresent(LooseNumber.self, forKey: .status)?.value == 1
        product = try container.decodeIfPresent(ProductRecord.self, forKey: .product)
    }
}

/// The `nutriments` object, read for the eight per-100 keys only; upstream spells them
/// `_100g` whether the product is sold by mass or by volume. Open Food Facts
/// reports energy in kcal and kJ (kJ alone is divided by 4.184) and sodium in grams,
/// or only salt, which is sodium times 2.5; the app stores sodium in milligrams. A
/// value outside what manual entry accepts (0 to `Formatters.maximumNutrientValue`)
/// is treated as unknown, so a bad upstream edit never reaches Health.
private nonisolated struct Nutriments: Decodable {
    let per100g: Nutrition

    private enum Keys: String, CodingKey {
        case energyKcal = "energy-kcal_100g"
        case energy = "energy_100g"
        case proteins = "proteins_100g"
        case carbohydrates = "carbohydrates_100g"
        case fat = "fat_100g"
        case saturatedFat = "saturated-fat_100g"
        case fiber = "fiber_100g"
        case sugars = "sugars_100g"
        case sodium = "sodium_100g"
        case salt = "salt_100g"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        func value(_ key: Keys) throws -> Double? {
            guard let value = try container.decodeIfPresent(LooseNumber.self, forKey: key)?.value else { return nil }
            return (0...Formatters.maximumNutrientValue).contains(value) ? value : nil
        }
        let energy = try value(.energyKcal) ?? value(.energy).map { $0 / 4.184 }
        let sodiumGrams = try value(.sodium) ?? value(.salt).map { $0 / 2.5 }
        per100g = Nutrition(
            energy: energy,
            protein: try value(.proteins),
            carbohydrates: try value(.carbohydrates),
            fatTotal: try value(.fat),
            fatSaturated: try value(.saturatedFat),
            fiber: try value(.fiber),
            sugar: try value(.sugars),
            sodium: sodiumGrams.map { $0 * 1000 }
        )
    }
}

/// A number Open Food Facts may serialise as a JSON number or as a string; anything
/// that is neither, or not finite, decodes as `nil` rather than failing the product.
private nonisolated struct LooseNumber: Decodable {
    let value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
        } else if let text = try? container.decode(String.self) {
            let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            value = Double(normalized).flatMap { $0.isFinite ? $0 : nil }
        } else {
            value = nil
        }
    }
}
