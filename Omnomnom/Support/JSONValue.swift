import Foundation

/// A JSON value this app can read and hand straight back out unchanged.
///
/// It exists for one requirement, and it is not a general convenience. A conversation that
/// has tool calls in it is replayed on every round trip: the model's turn goes back into
/// the next request, and the blocks in that turn — the tool call, and on current models a
/// reasoning block whose text is withheld but whose signature is not — belong to the
/// conversation that produced them. Rebuilding that turn out of only the parts this app
/// happens to understand would be an edit to the history, and a model is entitled to
/// refuse one. So the loop keeps what it was sent and sends it again.
///
/// Integers are their own case because re-emitting `1` as `1.0` is a change too, and this
/// type's whole job is to make no changes.
nonisolated enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Tried in the order that keeps each value in its own shape: `Bool` before `Int`
    /// because a decoder asked for a bool will not take a number, and `Int` before
    /// `Double` because a decoder asked for an int will not take 1.5.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a JSON value this app can carry"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Reading

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// A member of this value, when it is an object that has one.
    ///
    /// A subscript rather than a `string(_:)` convenience, which would have been one
    /// overload away from `JSONValue.string(_:)` the case constructor. Writing a value out
    /// needs no helper at all: `.object(["type": .string("text")])` is the case.
    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}
