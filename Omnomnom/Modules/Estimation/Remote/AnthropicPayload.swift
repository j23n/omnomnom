import Foundation

/// Everything about one round trip to the Messages API that is pure: the request body, the
/// request, and the reading of what comes back. Kept apart from `AnthropicLineResolver` so
/// all of it can be tested without a network.
///
/// Nothing here logs. A body holds what the user typed and, when they allowed it, their
/// photograph, and an error from the API can quote either back. That belongs on screen,
/// where the user is already looking, and never in a log a crash report could carry.
///
/// **Why this is not `RemoteEstimatePayload` with a different URL.** The two are different
/// protocols wearing similar clothes, and the differences are each load-bearing here:
/// the system prompt is a field rather than a message, `max_tokens` is required, an image
/// is a base64 block rather than a `data:` URL, the schema lives in `output_config.format`
/// with no name or strict flag around it, the answer is a list of content blocks rather
/// than a choice, and `temperature` is rejected outright on current models — which the
/// other path sends, at 0, for determinism. Folding both into one encoder would have meant
/// a flag on every field.
///
/// The loss of `temperature: 0` is worth stating plainly: the same line can resolve two
/// ways on consecutive days, which the on-device path's greedy sampling rules out. What
/// actually keeps a repeat stable is phrase memory, which answers before any model is
/// asked, so the case where it matters most does not reach here at all.
nonisolated enum AnthropicPayload {
    /// The only version header the API takes.
    static let version = "2023-06-01"
    /// Offered in Settings as the address to use, and the one the field is placeheld with.
    static let defaultBaseURL = "https://api.anthropic.com/v1"
    /// Offered as the model to use. A plain field rather than a picker, because the model
    /// names move faster than this app ships and someone with access to a newer one should
    /// not have to wait for a release to type it in.
    static let defaultModel = "claude-opus-5-5"
    /// Room for the searches and the answer. An answer is a few hundred tokens; this is
    /// generous because being cut off mid-object costs a whole request to discover.
    static let maximumTokens = 4_096
    /// Thinking cannot be turned off on the current models and effort is what governs its
    /// depth. Low: naming the foods on a plate and picking rows from a list is not a
    /// problem that repays deliberation, and the composer is on a twenty-second budget.
    static let effort = "low"
    /// How long one round trip may take. Shorter than the OpenAI-compatible path's 45,
    /// because there are several of these in a resolution rather than one.
    static let timeout: TimeInterval = 30
    /// How many round trips one line may take before the app gives up. Enough for a model
    /// to search for every food, read the results and search again for the ones that found
    /// nothing; small enough that a model which will not stop searching costs a bounded
    /// number of requests rather than a bill.
    static let maximumRounds = 5
    /// A reply is a few kilobytes. Anything above this is not one.
    static let maximumBodySize = 1 << 20
    /// Longest side of the photo that is sent, in pixels.
    ///
    /// Larger than the OpenAI-compatible path's 768, which is sized for a self-hosted
    /// server on a phone connection. Here the cost is visual tokens, charged as
    /// ceil(w/28) × ceil(h/28): 1024 is 1,369 of them against 784, and both are far under
    /// the 2,576-pixel long edge at which the API would downscale it itself. The quality
    /// is higher for the same reason — compression artefacts cost accuracy, and this is
    /// one request rather than a stream.
    static let imagePixelSize = 1_024
    static let imageQuality = 0.85

    static let foodTool = "search_foods"
    static let productTool = "search_products"

    /// Said when a reply arrives that cannot be read as an answer. The same sentence as the
    /// other two decoding failures, because to the user it is the same event.
    static let unreadableAnswer = "the model's answer could not be read. Try again."
    /// Said when the reply stopped at the token limit, which is half a JSON object and
    /// fails to parse for a reason the user can act on.
    static let cutOff = "the model stopped before it finished answering. Try a shorter description."
    /// Said when the model is still searching after `maximumRounds`.
    static let keptSearching = "the model kept searching without answering. Try again, or describe the meal more plainly."
    /// Said when a photo is the only thing given and photos are not allowed out.
    static let photosNotAllowed = """
        Claude is not allowed to see your photos. Turn that on in Settings, \
        or describe the meal in words.
        """

    // MARK: - Request

    /// The blocks of the opening message: the photo first where there is one, then the
    /// words. In that order on purpose — an image before its text reads better than after
    /// it, and this is the one place the order is ours to choose.
    ///
    /// When photos are off and words came with the picture, those words are sent as an
    /// ordinary description: asking about "the attached photo" when nothing is attached
    /// invites the model to invent what it cannot see.
    static func opening(for input: EstimationInput, sendsPhotos: Bool) throws -> [JSONValue] {
        switch input {
        case .text(let line):
            return [text(LinePrompt.text(line: line))]
        case .photo(let data, let line):
            guard sendsPhotos else {
                let hint = LinePrompt.clean(line ?? "")
                guard !hint.isEmpty else { throw EstimationError.unavailable(photosNotAllowed) }
                return [text(LinePrompt.text(line: hint))]
            }
            guard let image = PhotoData.downscaled(data, maxPixelSize: imagePixelSize),
                  let jpeg = PhotoData.jpegData(image, quality: imageQuality)
            else { throw EstimationError.failed("the photo could not be read.") }
            return [self.image(jpeg), text(LinePrompt.photo(line: line))]
        }
    }

    static func text(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    static func image(_ jpeg: Data) -> JSONValue {
        .object([
            "type": .string("image"),
            "source": .object([
                "type": .string("base64"),
                "media_type": .string("image/jpeg"),
                "data": .string(jpeg.base64EncodedString()),
            ]),
        ])
    }

    /// One search's answer, against the call it answers. Every `tool_use` block has to come
    /// back with a `tool_result` carrying its id, including the ones this app cannot run —
    /// a call left unanswered makes the next request invalid.
    static func toolResult(id: String, text: String, isError: Bool = false) -> JSONValue {
        var block: [String: JSONValue] = [
            "type": .string("tool_result"),
            "tool_use_id": .string(id),
            "content": .array([self.text(text)]),
        ]
        if isError { block["is_error"] = .bool(true) }
        return .object(block)
    }

    /// The JSON body of one request. `messages` is the whole conversation so far: the API
    /// keeps nothing between calls, so a tool loop resends what it has.
    /// Throws rather than sending an empty model, which is the second defence against the
    /// mistake that `AnthropicLineResolver.init` now prevents: a caller that forgets to
    /// resolve the settings gets a sentence naming the field instead of a 400 the user
    /// cannot connect to anything they typed.
    static func body(
        model: String, messages: [AnthropicMessage], searchesProducts: Bool
    ) throws -> Data {
        let named = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else {
            throw EstimationError.unavailable("Add the model to ask for in Settings, or clear the field to use \(defaultModel).")
        }
        // Deliberately absent: `thinking`, which is on by default and cannot be switched
        // off on the current models, so sending anything for it is at best a no-op and at
        // worst a 400; and `temperature`, which is rejected outright.
        let request: JSONValue = .object([
            "model": .string(named),
            "max_tokens": .int(maximumTokens),
            "system": .string(LinePrompt.instructions),
            "messages": .array(messages.map(\.json)),
            "tools": .array(tools(searchesProducts: searchesProducts)),
            "output_config": .object([
                "effort": .string(effort),
                "format": .object([
                    "type": .string("json_schema"),
                    "schema": answerSchema,
                ]),
            ]),
        ])
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw EstimationError.failed("the request could not be built.")
        }
    }

    /// The POST. The key goes in `x-api-key` rather than a bearer token, which is the one
    /// header difference that silently fails rather than erroring usefully if it is wrong.
    static func request(url: URL, key: String?, body: Data) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        if let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        return request
    }

    /// The tools, in a fixed order so the request prefix is stable between rounds.
    static func tools(searchesProducts: Bool) -> [JSONValue] {
        var tools = [
            tool(
                named: foodTool, description: LinePrompt.foodToolDescription,
                term: "A food to look for, in whatever wording you want to try"
            )
        ]
        if searchesProducts {
            tools.append(
                tool(
                    named: productTool, description: LinePrompt.productToolDescription,
                    term: "A product name or brand to look for"
                )
            )
        }
        return tools
    }

    // MARK: - Response

    /// What one reply says to do next.
    nonisolated enum Step: Hashable, Sendable {
        /// Searches to run here, with the turn they came in so it can be replayed intact.
        case searches(turn: [JSONValue], calls: [ToolCall])
        /// The line, resolved.
        case answer(ResolvedLine)
    }

    /// One search the model asked for. `tool` is whatever name came back rather than a
    /// case of an enum, so a name this app does not know can be answered with an error
    /// instead of being dropped — a dropped call leaves the next request invalid.
    nonisolated struct ToolCall: Hashable, Sendable {
        let id: String
        let tool: String
        let term: String
    }

    /// The reply, read. Throws `EstimationError` for anything that cannot continue.
    static func step(from data: Data) throws -> Step {
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw EstimationError.failed(unreadableAnswer)
        }
        switch reply.stopReason {
        case "refusal":
            throw EstimationError.guardrail
        case "max_tokens":
            throw EstimationError.failed(cutOff)
        default:
            break
        }

        let calls = reply.content.compactMap(toolCall)
        if !calls.isEmpty {
            return .searches(turn: reply.content, calls: calls)
        }
        // The first text block, not all of them joined: with a schema in force the answer
        // is one block, and joining would only help a reply that is not the shape asked
        // for — where the first brace to the last one is a better guess anyway.
        guard let spoken = reply.content.first(where: { $0["type"]?.stringValue == "text" })?["text"]?.stringValue,
              let object = RemoteEstimatePayload.jsonObject(in: spoken),
              let body = object.data(using: .utf8),
              let answer = try? JSONDecoder().decode(ResolvedLine.self, from: body)
        else { throw EstimationError.failed(unreadableAnswer) }
        return .answer(answer)
    }

    /// One `tool_use` block as a call, or `nil` for any other block.
    private static func toolCall(_ block: JSONValue) -> ToolCall? {
        guard block["type"]?.stringValue == "tool_use",
              let id = block["id"]?.stringValue,
              let name = block["name"]?.stringValue
        else { return nil }
        // A missing or non-string term is an empty one rather than a dropped call: the
        // call still has to be answered, and a search for nothing answers with nothing.
        return ToolCall(id: id, tool: name, term: block["input"]?["term"]?.stringValue ?? "")
    }

    /// What the body says about a failure, in whichever shape it arrived.
    ///
    /// The envelope first, and a capped preview of the body when that finds nothing. The
    /// fallback is worth having rather than tidy: "the API answered 400." with no detail
    /// is a dead end for whoever has to fix it, and the one thing that always names the
    /// offending field is the body. Shown and never logged — an error body can quote back
    /// what the user typed.
    static func detail(in body: Data) -> String? {
        if let message = RemoteEstimatePayload.message(in: body) { return message }
        let collapsed = RemoteEstimatePayload.preview(of: body)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(RemoteEstimatePayload.maximumErrorMessageLength))
    }

    /// What to show for a non-2xx answer.
    ///
    /// The error envelope and the words servers use for a prompt that did not fit are the
    /// other remote path's, reused rather than copied: an error body shaped
    /// `{"error": {"message": …}}` is read the same way whoever sent it.
    static func error(status: Int, body: Data) -> EstimationError {
        let reason = detail(in: body)
        switch status {
        case 401, 403:
            return .unavailable("The API refused the key. Check it in Settings.")
        case 404:
            return .unavailable("The API answered 404. Check the address and the model name in Settings.")
        case 413:
            return .tooLong
        case 429:
            return .failed("too many requests; try again in a moment.")
        case 529:
            return .failed("the API is overloaded right now. Try again in a moment.")
        default:
            guard let reason else { return .failed("the API answered \(status).") }
            let lowered = reason.lowercased()
            if RemoteEstimatePayload.contextMarkers.contains(where: lowered.contains) { return .tooLong }
            return .failed("the API answered \(status): \(reason)")
        }
    }
}

// MARK: - Request bodies

/// One turn of the conversation. `content` is always a list of blocks, which is what makes
/// the model's own turn replayable: the blocks it sent go back exactly as they arrived.
nonisolated struct AnthropicMessage: Hashable, Sendable {
    let role: String
    let content: [JSONValue]

    static func user(_ content: [JSONValue]) -> AnthropicMessage {
        AnthropicMessage(role: "user", content: content)
    }

    static func assistant(_ content: [JSONValue]) -> AnthropicMessage {
        AnthropicMessage(role: "assistant", content: content)
    }

    /// The turn as it is sent. The blocks are already `JSONValue`, so the whole request
    /// body is one value and needs no `Encodable` type of its own.
    var json: JSONValue {
        .object(["role": .string(role), "content": .array(content)])
    }
}

/// One tool, as the request declares it. `strict` keeps the arguments schema-valid, which
/// is what makes reading `input.term` safe without a fallback for every shape.
///
/// Every search takes the one argument.
extension AnthropicPayload {
    static func tool(named name: String, description: String, term: String) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "strict": .bool(true),
            "input_schema": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("term")]),
                "properties": .object(["term": JSONSchema.field("string", term)]),
            ]),
        ])
    }

    /// The schema for `ResolvedLine`, written out rather than derived, in the shape it is
    /// sent as. Nested dictionaries rather than a tree of single-use `Encodable` structs:
    /// the schema is a constant, so the types only restated the JSON a level further from
    /// it, and the keys strict mode spells with an underscore needed a `CodingKeys` each.
    ///
    /// Only the keywords strict mode accepts appear: a `minimum` or `maximum` on the grams
    /// and a `maxItems` on the array are each rejected, so those bounds are stated in the
    /// descriptions, where a model still reads them, and enforced afterwards by
    /// `EstimateConversion`, where it counts. The same constraint the OpenAI-compatible
    /// schema works under, for the same reason.
    ///
    /// The two enumerations are spelled out rather than read off the type: neither
    /// `EstimatedMeal` nor `VerdictCertainty` is `CaseIterable`, both being generable enums
    /// that nothing has needed to enumerate before. Same bargain the OpenAI-compatible
    /// schema makes, and the same place to look when a case is added.
    static let answerSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("items"), .string("meal"), .string("note")]),
        "properties": .object([
            "items": .object([
                "type": .string("array"),
                "description": .string(
                    "One entry per distinct food or drink in the meal, at most 12 of them"
                ),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("name"), .string("candidate"), .string("grams"),
                        .string("certainty"), .string("implausible"),
                    ]),
                    "properties": .object([
                        "name": JSONSchema.field(
                            "string",
                            "Short plain name of the food, as the person who ate it would say it"
                        ),
                        "candidate": JSONSchema.field(
                            "integer",
                            "The id of the chosen candidate row, or 0 when neither search holds this food"
                        ),
                        "grams": JSONSchema.field(
                            "number",
                            "Weight of the portion eaten, in grams, between 1 and 3000"
                        ),
                        "certainty": JSONSchema.choice(
                            of: ["certain", "probable", "unsure"],
                            "How sure the choice of row is"
                        ),
                        "implausible": JSONSchema.field(
                            "boolean",
                            "True only when the amount eaten and the chosen food do not go together"
                        ),
                    ]),
                ]),
            ]),
            "meal": JSONSchema.choice(
                of: ["breakfast", "lunch", "dinner", "snack"],
                "Which meal these foods belong to, judged from the foods themselves and not from the time of day"
            ),
            "note": JSONSchema.field(
                "string", "One short sentence on what you assumed, and whether you are unsure"
            ),
        ]),
    ])
}

// MARK: - Response bodies

/// A reply, read down to the two things that decide what happens next: the blocks, kept as
/// they arrived, and why the model stopped.
private nonisolated struct Reply: Decodable {
    let content: [JSONValue]
    /// Lowercased, so "refusal", "max_tokens" and "tool_use" can be compared directly.
    let stopReason: String?

    private enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? container.decode([JSONValue].self, forKey: .content)) ?? []
        stopReason = (try? container.decode(String.self, forKey: .stopReason))?.lowercased()
    }
}
