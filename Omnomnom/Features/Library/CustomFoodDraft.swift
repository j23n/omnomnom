import Foundation

/// Value-type state of the custom food editor: a name, the typed per-100 g text for
/// each nutrient and the photo. Energy is required; a blank field means the value is unknown.
nonisolated struct CustomFoodDraft: Hashable, Sendable {
    var name = ""
    /// The stored-size photo of the food; `nil` for none.
    var photo: Data?
    private var fields: [Nutrient: String] = [:]

    init() {}

    /// Prefilled from an existing food's values.
    init(name: String, per100g: Nutrition, photo: Data? = nil) {
        self.name = name
        self.photo = photo
        for nutrient in Nutrient.allCases {
            if let value = per100g[nutrient] {
                fields[nutrient] = Formatters.fieldText(value)
            }
        }
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func text(for nutrient: Nutrient) -> String {
        fields[nutrient] ?? ""
    }

    mutating func setText(_ text: String, for nutrient: Nutrient) {
        fields[nutrient] = text
    }

    /// The values to store, or `nil` when energy is blank or any field holds something
    /// that is not a number from 0 up to `Formatters.maximumNutrientValue`.
    var per100g: Nutrition? {
        var result = Nutrition()
        for nutrient in Nutrient.allCases {
            let text = self.text(for: nutrient).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard let value = Formatters.parseNutrientValue(text) else { return nil }
            result[nutrient] = value
        }
        guard result.energy != nil else { return nil }
        return result
    }

    /// Whether a field holds text that does not parse; blank is fine.
    func isInvalid(_ nutrient: Nutrient) -> Bool {
        let text = self.text(for: nutrient).trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && Formatters.parseNutrientValue(text) == nil
    }

    var isValid: Bool {
        !trimmedName.isEmpty && per100g != nil
    }
}
