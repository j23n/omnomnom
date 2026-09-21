import Foundation

/// One product as Open Food Facts describes it, reduced to what the app keeps: the
/// code, a name, the first brand, and the eight nutrients per 100 g.
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

    /// Longest name or brand kept; upstream text is community-edited and unbounded.
    static let maximumTextLength = 200
    let per100g: Nutrition

    /// A record without energy cannot be logged, so the flow falls back to manual entry.
    var isUsable: Bool {
        per100g.energy != nil
    }

    init(code: String, name: String?, brand: String?, per100g: Nutrition) {
        self.code = code
        self.name = name
        self.brand = brand
        self.per100g = per100g
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case nutriments
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .productName))
        let brands = try container.decodeIfPresent(String.self, forKey: .brands) ?? ""
        brand = Self.trimmed(brands.split(separator: ",", maxSplits: 1).first.map(String.init))
        per100g = try container.decodeIfPresent(Nutriments.self, forKey: .nutriments)?.per100g ?? .empty
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

/// The `nutriments` object, read for the eight per-100 g keys only. Open Food Facts
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
