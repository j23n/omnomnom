import Foundation

/// The leaf shapes a JSON Schema is built from, shared by the two remote paths.
///
/// Both backends want a schema for the same answer and both are given one as a literal
/// rather than as a tree of single-use `Encodable` structs: the schema is a constant, so
/// the types only restated the JSON a level further from it, and every key the spec spells
/// with an underscore or reserves as a Swift keyword needed a `CodingKeys` of its own.
///
/// Only these two shapes are here because only these two repeat. Whatever a schema says
/// above a leaf — which keys are required, whether extra ones are refused — reads better
/// written out at the point it applies.
nonisolated enum JSONSchema {
    /// One `{"type": ..., "description": ...}` leaf.
    static func field(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    /// Which meal the foods belong to. Both schemas ask for this, with the same four
    /// words and the same sentence, because it is the same question — and a sentence sent
    /// to two models should not be able to drift between them.
    static let mealField = choice(
        of: ["breakfast", "lunch", "dinner", "snack"],
        "Which meal these foods belong to, judged from the foods themselves and not from the time of day"
    )

    /// A string leaf narrowed to a fixed set of words. `enum` is the schema's own spelling
    /// and a Swift keyword, which is the whole reason the struct form needed `CodingKeys`.
    static func choice(of allowed: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(allowed.map(JSONValue.string)),
            "description": .string(description),
        ])
    }
}
