import CoreGraphics
import Foundation

/// How much the request asks of the endpoint.
///
/// "OpenAI-compatible" is a family resemblance, not a specification, so the request is
/// made twice at most. The strict attempt sends a JSON Schema the answer must match and
/// temperature 0, so the same meal gives the same numbers the way the on-device path's
/// greedy sampling does. Neither of those is universal: servers that implement only
/// `{"type":"json_object"}` reject the schema, and OpenAI's own reasoning models reject
/// any temperature but their default. The plain attempt therefore drops both and states
/// the shape in words instead, which is the least an OpenAI-compatible endpoint can be
/// asked for and still answer usefully.
nonisolated enum RemoteEstimateMode: Hashable, Sendable {
    case strict
    case plain
}

/// What one request's user message carries: the words, and the photo when the user has
/// allowed photos to leave the device.
nonisolated enum RemoteEstimateContent: Hashable, Sendable {
    case text(String)
    case textAndImage(text: String, dataURL: String)
}

/// Everything about a remote estimate that is pure: the request body, the request itself,
/// and the reading of what comes back. Kept apart from `RemoteMealEstimator` so all of it
/// can be tested without a server.
///
/// Nothing here logs. The body holds what the user typed and, when they allowed it, their
/// photograph; an endpoint's error text can quote either back. That belongs on screen,
/// where the user is already looking, and never in a log a crash report could carry.
nonisolated enum RemoteEstimatePayload {
    /// Longest side of the photo that is sent, in pixels.
    ///
    /// Smaller than the 1024 the on-device model is given, because this one is base64 in
    /// a request body rather than a buffer handed across a process: the encoding is a
    /// third larger again, and a full camera JPEG this way is megabytes uploaded over a
    /// phone connection. A plate of food is still legible at 768.
    static let imagePixelSize = 768
    /// JPEG quality of the sent photo; below this the texture that tells rice from
    /// couscous starts to go.
    static let imageQuality = 0.6
    /// How long one request may take, in seconds. Generous because a local server on
    /// middling hardware is genuinely slow, bounded because a composer that waits
    /// forever is worse than one that fails and lets the user type the meal instead.
    static let timeout: TimeInterval = 45
    /// Name the schema is sent under; servers echo it in errors.
    static let schemaName = "meal_estimate"
    /// An estimate is a few hundred bytes. Anything above this is not one, and decoding
    /// it would only spend memory to fail.
    static let maximumBodySize = 1 << 20
    /// How much of an error body is examined; the useful part of one is at the front.
    static let maximumErrorPreview = 4096
    /// How much of an endpoint's own words are shown to the user.
    static let maximumErrorMessageLength = 200

    /// Said when an answer arrives that cannot be read as an estimate. The same sentence
    /// as the on-device decoding failure, because to the user it is the same event.
    static let unreadableAnswer = "the endpoint's answer could not be read. Try again."

    /// Said when a photo is the only thing given and photos are not allowed out.
    static let photosNotAllowed = """
        This endpoint is not allowed to see your photos. Turn that on in Settings, \
        or describe the meal in words.
        """

    // MARK: - Prompt

    /// The system message. The same instructions the on-device model is given, so the two
    /// backends are asked for the same thing and a draft from either reads the same.
    static func systemMessage(for mode: RemoteEstimateMode) -> String {
        switch mode {
        case .strict: EstimationPrompt.instructions
        case .plain: "\(EstimationPrompt.instructions)\n\(shapeInstruction)"
        }
    }

    /// What the schema says, in words, for the plain attempt.
    ///
    /// The literal word JSON has to appear in a message: OpenAI refuses
    /// `{"type":"json_object"}` outright unless it does, and it is the only hint a
    /// chat-tuned local model gets about the shape.
    static let shapeInstruction = """
        Answer with one JSON object and nothing else: no explanation, no code fence. The object has exactly these keys:
        {"items": [{"name": "string", "lookupTerm": "string", "grams": number}], "meal": "breakfast" or "lunch" or "dinner" or "snack", "note": "string"}
        grams is a plain number of grams, between 1 and 3000, not a string and not a range. List at most 12 items.
        """

    // MARK: - Request

    /// What to send for this input, or a failure the user can act on.
    ///
    /// The photo switch is honoured here rather than in the estimator, so that "a photo
    /// was not sent" is a decision one test can pin down. When photos are off and words
    /// came with the picture, those words are sent as an ordinary description: asking
    /// about "the attached photo" when nothing is attached invites the model to invent
    /// what it cannot see.
    static func content(for input: EstimationInput, sendsPhotos: Bool) throws -> RemoteEstimateContent {
        switch input {
        case .text(let description):
            return .text(EstimationPrompt.text(description: description))
        case .photo(let data, let description):
            guard sendsPhotos else {
                let hint = EstimationPrompt.clean(description ?? "")
                guard !hint.isEmpty else { throw EstimationError.unavailable(photosNotAllowed) }
                return .text(EstimationPrompt.text(description: hint))
            }
            guard let dataURL = imageDataURL(for: data) else {
                throw EstimationError.failed(EstimationError.unreadablePhoto)
            }
            return .textAndImage(text: EstimationPrompt.photoText(description: description), dataURL: dataURL)
        }
    }

    /// The photo as the `data:` URL the vision shape expects, downscaled and re-encoded
    /// first through the same ImageIO path the rest of the app uses, or `nil` when the
    /// bytes are not an image this device can read.
    static func imageDataURL(for data: Data) -> String? {
        guard let image = PhotoData.downscaled(data, maxPixelSize: imagePixelSize),
              let jpeg = PhotoData.jpegData(image, quality: imageQuality)
        else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    /// The JSON body of one chat-completions request.
    static func body(model: String, mode: RemoteEstimateMode, content: RemoteEstimateContent) throws -> Data {
        let spoken: JSONValue
        switch content {
        case .text(let text):
            spoken = .string(text)
        case .textAndImage(let text, let dataURL):
            // The shape OpenAI's vision requests use and every compatible server copied:
            // the content field becomes a list of parts as soon as an image is involved.
            spoken = .array([
                .object(["type": .string("text"), "text": .string(text)]),
                .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(dataURL)]),
                ]),
            ])
        }
        var request: [String: JSONValue] = [
            "model": .string(model.trimmingCharacters(in: .whitespacesAndNewlines)),
            "messages": .array([
                .object([
                    "role": .string("system"), "content": .string(systemMessage(for: mode)),
                ]),
                .object(["role": .string("user"), "content": spoken]),
            ]),
            "response_format": responseFormat(for: mode),
        ]
        // An absent temperature is an absent key rather than a null, which more than one
        // server rejects, and only the strict attempt sends one at all.
        if mode == .strict { request["temperature"] = .double(0) }
        do {
            return try JSONEncoder().encode(JSONValue.object(request))
        } catch {
            throw EstimationError.failed("the request could not be built.")
        }
    }

    /// How much of the answer's shape the request states, which is what the two modes
    /// differ by. The strict attempt sends the schema; the plain one asks only for JSON
    /// and says the shape in words in the system message instead.
    static func responseFormat(for mode: RemoteEstimateMode) -> JSONValue {
        switch mode {
        case .plain:
            .object(["type": .string("json_object")])
        case .strict:
            .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string(schemaName),
                    // Strict so a server that honours it cannot hand back extra keys or
                    // leave one out. Servers that do not understand the flag ignore it.
                    "strict": .bool(true),
                    "schema": mealEstimateSchema,
                ]),
            ])
        }
    }

    /// The JSON Schema for `MealEstimate`, written out rather than derived.
    ///
    /// `MealEstimate` carries its shape in `@Generable` and `@Guide` macros that only the
    /// on-device framework reads; there is no runtime description of it to walk, so this is
    /// the one place where the two backends' idea of the shape can drift apart. The
    /// descriptions deliberately repeat the `@Guide` wording.
    ///
    /// Only the keywords OpenAI's strict mode accepts appear: `maxItems` on the array and a
    /// `minimum`/`maximum` on the grams are both a 400 there, so those bounds are stated in
    /// the descriptions and in the prompt, where a model still reads them, and enforced by
    /// `EstimateConversion` afterwards, where it counts.
    static let mealEstimateSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("items"), .string("meal"), .string("note")]),
        "properties": .object([
            "items": .object([
                "type": .string("array"),
                "description": .string(
                    "Each distinct food or drink in the meal, at most 12 of them"
                ),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([
                        .string("name"), .string("lookupTerm"), .string("grams"),
                    ]),
                    "properties": .object([
                        "name": JSONSchema.field(
                            "string",
                            "Short plain name of the food or drink, as the person who ate it would say it"
                        ),
                        "lookupTerm": JSONSchema.field(
                            "string",
                            "The same food in the generic, unbranded wording a nutrition database uses"
                        ),
                        "grams": JSONSchema.field(
                            "number",
                            "Estimated weight of the portion eaten, in grams, between 1 and 3000"
                        ),
                    ]),
                ]),
            ]),
            "meal": JSONSchema.mealField,
            "note": JSONSchema.field(
                "string",
                "One short sentence on what was assumed, and whether the estimate is uncertain"
            ),
        ]),
    ])

    /// The POST, with the key when there is one. A great many self-hosted servers want no
    /// key at all, so a missing one sends no header rather than an empty bearer that looks
    /// like a mistake.
    static func request(url: URL, key: String?, body: Data) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Failures

    /// Markers that say a rejection was about what the strict attempt asked for rather
    /// than about the meal.
    static let strictRejectionMarkers = [
        "schema", "response_format", "response format", "structured output", "temperature",
    ]

    /// Statuses that say nothing about the request's shape, so retrying it differently
    /// would only spend a second request to be told the same thing.
    static let unretryableStatuses = [401, 403, 408, 429]

    /// Whether a rejection reads like the endpoint refusing the strict attempt itself.
    ///
    /// There is no status code for this and no error code for it either. A server that
    /// does not implement `json_schema` answers with a 400 (llama.cpp, LM Studio), a 422
    /// naming the offending field (anything built on FastAPI, vLLM among them) or
    /// occasionally a 500 from a proxy in front of it; a reasoning model that will not
    /// take temperature 0 answers 400 as well. The only thing they agree on is that the
    /// words appear somewhere in the body, so the body is what is searched. A false
    /// positive costs one extra request; a false negative shows the user a failure they
    /// cannot do anything about.
    static func rejectsStrictRequest(status: Int, body: Data) -> Bool {
        guard !(200..<300).contains(status), !unretryableStatuses.contains(status) else { return false }
        let text = preview(of: body).lowercased()
        return strictRejectionMarkers.contains { text.contains($0) }
    }

    /// What to show for a non-2xx answer. The endpoint's own words are included where it
    /// gave any: it is the user's own server, and "answered 400" alone tells them nothing
    /// about which field it disliked.
    static func error(status: Int, body: Data) -> EstimationError {
        let reason = message(in: body)
        switch status {
        case 401, 403:
            return .unavailable("The endpoint refused the API key. Check it in Settings.")
        case 404:
            return .unavailable("The endpoint answered 404. Check the address and the model name in Settings.")
        case 413:
            // Semantically the right case, though its sentence names the on-device model.
            return .tooLong
        case 429:
            return .failed(EstimationError.rateLimited)
        default:
            if let reason {
                if contains(reason, any: contextMarkers) { return .tooLong }
                if contains(reason, any: refusalMarkers) { return .guardrail }
                return .failed("the endpoint answered \(status): \(reason)")
            }
            return .failed("the endpoint answered \(status).")
        }
    }

    /// Words a server uses when the prompt did not fit.
    static let contextMarkers = [
        "context length", "context window", "context_length", "maximum context", "too many tokens",
    ]
    /// Words a server uses when the model or a filter in front of it declined.
    static let refusalMarkers = ["content filter", "content_filter", "content policy", "content_policy"]

    private static func contains(_ text: String, any markers: [String]) -> Bool {
        let lowered = text.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    /// The sentence inside an error body, in whichever of the three shapes the family
    /// uses, capped so a server that returns a stack trace does not fill the sheet.
    static func message(in body: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(RemoteErrorEnvelope.self, from: body),
              let message = decoded.message
        else { return nil }
        let collapsed = message.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumErrorMessageLength))
    }

    /// The front of a body as text, for searching. Never logged.
    static func preview(of body: Data) -> String {
        String(decoding: body.prefix(maximumErrorPreview), as: UTF8.self)
    }

    // MARK: - Response

    /// The estimate inside a model's reply.
    ///
    /// Read tolerantly on purpose: `EstimateConversion` clamps and trims downstream, so
    /// the only job here is to hand it something rather than nothing. A reply that holds
    /// no object at all is the one thing that cannot be recovered.
    static func estimate(from reply: String) throws -> MealEstimate {
        guard let text = jsonObject(in: reply), let data = text.data(using: .utf8) else {
            throw EstimationError.failed(unreadableAnswer)
        }
        do {
            return try JSONDecoder().decode(RemoteEstimateDTO.self, from: data).estimate
        } catch {
            throw EstimationError.failed(unreadableAnswer)
        }
    }

    /// The outermost braced object in a reply, or `nil` when there is none.
    ///
    /// Only a server that honours a schema returns bare JSON. Everything else wraps it:
    /// a chat-tuned model fences it as ```json, puts "Here is the estimate:" in front of
    /// it, or adds a closing remark after it. The first brace to the last one is the
    /// answer and the rest is conversation, which also disposes of the fence without
    /// having to recognise one.
    static func jsonObject(in reply: String) -> String? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(reply[start...end])
    }
}

// MARK: - Response bodies

/// What a chat-completions answer is read down to: the text of the first choice, why it
/// stopped, and the refusal field OpenAI added when a model declines in words.
nonisolated struct RemoteCompletionResponse: Sendable, Decodable {
    let content: String?
    /// Lowercased, so "stop", "length" and "content_filter" can be compared directly.
    let finishReason: String?
    let refusal: String?

    private enum CodingKeys: String, CodingKey {
        case choices
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A proxy that failed upstream answers 200 with no choices at all, so an empty
        // list is a shape to read rather than an error to decode.
        let first = (try? container.decode([RemoteChoice].self, forKey: .choices))?.first
        content = first?.message?.content
        finishReason = first?.finishReason?.lowercased()
        refusal = first?.message?.refusal
    }
}

private nonisolated struct RemoteChoice: Decodable {
    let message: RemoteChoiceMessage?
    let finishReason: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

/// A choice's message. `content` is a string everywhere it matters, but some servers
/// return the same parts array they accept, so both are read.
private nonisolated struct RemoteChoiceMessage: Decodable {
    let content: String?
    let refusal: String?

    private enum CodingKeys: String, CodingKey {
        case content
        case refusal
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refusal = try? container.decode(String.self, forKey: .refusal)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decode([RemoteContentPart].self, forKey: .content) {
            content = parts.compactMap(\.text).joined()
        } else {
            content = nil
        }
    }
}

private nonisolated struct RemoteContentPart: Decodable {
    let text: String?
}

/// The error body, in each of the shapes the family uses: OpenAI's nested object, the
/// bare string a few servers send, and the `detail` a FastAPI-based server returns.
nonisolated struct RemoteErrorEnvelope: Sendable, Decodable {
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case message
        case detail
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decode(RemoteErrorBody.self, forKey: .error) {
            message = nested.message
        } else if let text = try? container.decode(String.self, forKey: .error) {
            message = text
        } else if let text = try? container.decode(String.self, forKey: .message) {
            message = text
        } else if let text = try? container.decode(String.self, forKey: .detail) {
            message = text
        } else {
            message = nil
        }
    }
}

private nonisolated struct RemoteErrorBody: Decodable {
    let message: String?
}

// MARK: - Estimate

/// The estimate as a model writes it, which is the schema's shape when the schema was
/// honoured and something near it when it was not. Every field recovers rather than
/// throws: a draft the user corrects beats a failure they cannot.
private nonisolated struct RemoteEstimateDTO: Decodable {
    let items: [EstimatedItem]
    let meal: EstimatedMeal
    let note: String

    private enum CodingKeys: String, CodingKey {
        case items
        case meal
        case note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? container.decode([RemoteItemDTO].self, forKey: .items)) ?? []).compactMap(\.item)
        // A model that was never shown the schema often leaves the meal out entirely.
        // Snack is the honest default: it is the slot that claims the least.
        let spelled = (try? container.decode(String.self, forKey: .meal))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        meal = spelled.flatMap(EstimatedMeal.init(rawValue:)) ?? .snack
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
    }

    var estimate: MealEstimate {
        MealEstimate(items: items, meal: meal, note: note)
    }
}

/// One item of a model's answer. `item` is `nil` only when the element was not an object
/// at all, so one stray string in the array costs that element and not the whole meal.
private nonisolated struct RemoteItemDTO: Decodable {
    let item: EstimatedItem?

    private enum CodingKeys: String, CodingKey {
        case name
        case lookupTerm
        // The rest of the API is snake_case and models write what they have seen, so a
        // camel-case key in a schema comes back snake-cased often enough to accept.
        case lookupTermSnake = "lookup_term"
        case grams
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            item = nil
            return
        }
        let name = (try? container.decode(String.self, forKey: .name)) ?? ""
        let term = (try? container.decode(String.self, forKey: .lookupTerm))
            ?? (try? container.decode(String.self, forKey: .lookupTermSnake))
            ?? ""
        let grams = (try? container.decode(RemoteGrams.self, forKey: .grams))?.value ?? 0
        item = EstimatedItem(name: name, lookupTerm: term, grams: grams)
    }
}

/// A weight as a JSON number, or as the string a model writes when it was never held to a
/// schema: "120", "120 g", "about 90". Anything that yields no number reads 0, which
/// `EstimateConversion` drops: a dropped row is honest, an invented weight is not.
private nonisolated struct RemoteGrams: Decodable {
    let value: Double

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : 0
        } else if let text = try? container.decode(String.self) {
            value = Self.number(in: text)
        } else {
            value = 0
        }
    }

    /// The first run of digits in `text`, with a decimal comma read as a point.
    static func number(in text: String) -> Double {
        var digits = ""
        for character in text.replacingOccurrences(of: ",", with: ".") {
            if character.isASCII, character.isNumber || character == "." {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        guard let value = Double(digits), value.isFinite else { return 0 }
        return value
    }
}
