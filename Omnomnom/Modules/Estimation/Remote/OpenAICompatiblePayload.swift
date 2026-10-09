import CoreGraphics
import Foundation

/// What one request's user message carries: the words, and the photo when the user has
/// allowed photos to leave the device.
nonisolated enum OpenAICompatibleContent: Hashable, Sendable {
    case text(String)
    case textAndImage(text: String, dataURL: String)
}

/// Everything about one round trip to an OpenAI-compatible chat-completions endpoint that
/// is pure: the request body, the request, and the reading of what comes back. Kept apart
/// from `OpenAICompatibleLineResolver` so all of it can be tested without a server.
///
/// Nothing here logs. A body holds what the user typed and, when they allowed it, their
/// photograph, and an endpoint's error text can quote either back. That belongs on screen,
/// where the user is already looking, and never in a log a crash report could carry.
///
/// **What this asks of an endpoint, and what it does not.** "OpenAI-compatible" is a family
/// resemblance rather than a specification, and this path used to answer that by asking
/// twice: once with a JSON Schema and `temperature: 0`, and again without them when the
/// server objected. There is no second attempt now, because the thing this request cannot
/// do without is tools — a model that cannot call the search has no way to see the database
/// and nothing to choose a row from. So the request asks for exactly one extra capability
/// and nothing else:
///
/// - `tools`, which is the path itself.
/// - No `response_format`. A strict schema alongside tools is the pair a self-hosted server
///   is likeliest to refuse, and with the retry gone a refusal would be the end of the
///   request rather than the start of a plainer one. The shape is stated in words instead,
///   which is the least an OpenAI-compatible endpoint can be asked for and still answer
///   usefully, and the answer is read with `jsonObject(in:)`, which already recovers an
///   object a chat-tuned model fenced or prefaced.
/// - No `temperature`. Sending 0 bought determinism and cost a hard 400 on a reasoning
///   model that will not take one; the plain attempt is what used to absorb that. The loss
///   is worth stating plainly: the same line can resolve two ways on consecutive days.
///   What keeps a repeat stable is phrase memory, which answers before any model is asked,
///   so the case where it matters most does not reach here at all.
nonisolated enum OpenAICompatiblePayload {
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
    /// How long one round trip may take, in seconds.
    ///
    /// Stays at the 45 it was chosen for when this path made one request, even though a
    /// line now takes several: the reason for the number is that a local server on
    /// middling hardware is genuinely slow to produce its first token, and cutting it
    /// would fail exactly the endpoints this path exists for. What bounds the wait
    /// instead is `LinePrompt.maximumRounds`.
    static let timeout: TimeInterval = 45
    /// A reply is a few kilobytes. Anything above this is not one, and decoding it would
    /// only spend memory to fail.
    static let maximumBodySize = 1 << 20
    /// How much of an error body is examined; the useful part of one is at the front.
    static let maximumErrorPreview = 4096
    /// How much of an endpoint's own words are shown to the user.
    static let maximumErrorMessageLength = 200

    /// Said when an answer arrives that cannot be read. The same event as the other
    /// paths' decoding failures and all but the same sentence; the noun differs because
    /// this endpoint is the user's own.
    static let unreadableAnswer = "the endpoint's answer could not be read. Try again."
    /// Said when the reply stopped at the token limit, which is half a JSON object and
    /// fails to parse for a reason the user can act on — and, on a server they run
    /// themselves, one they can go and change.
    static let cutOff = "the endpoint stopped before it finished answering; its reply limit may be very small."
    /// Said when the endpoint turned the request down over the tools in it.
    ///
    /// Its own sentence rather than the endpoint's words, because this is the one failure
    /// on this path that is about the server's capabilities rather than about the request:
    /// a server without tool support cannot read a line at all, however it is addressed,
    /// and the only things to do about it are to point the app elsewhere or to choose a
    /// provider that answers. Saying "the endpoint answered 400: ..." instead would be
    /// true and useless.
    static let toolsUnsupported = """
        This endpoint cannot call tools, which is how the app's own food database is \
        searched. Point it at a server that can, or choose a different provider in Settings.
        """

    /// Said when a photo is the only thing given and photos are not allowed out.
    static let photosNotAllowed = """
        This endpoint is not allowed to see your photos. Turn that on in Settings, \
        or describe the meal in words.
        """

    // MARK: - Prompt

    /// The system message: the instructions both drivers send, with the shape of the
    /// answer after them.
    ///
    /// A message with the system role, rather than the field the Messages API takes.
    static let systemMessage: JSONValue = .object([
        "role": .string("system"), "content": .string(instructions),
    ])

    static let instructions = "\(LinePrompt.instructions)\n\(answerShape)"

    /// The answer's shape, in words, because no schema is sent.
    ///
    /// The sentence about grams is load-bearing here in a way it was not before: the
    /// answer is decoded into `ResolvedLineItem`, which reads a weight as a number and
    /// nothing else, where the estimate shape this path used to ask for also read "220 g"
    /// out of a string. A model that writes a weight as words now costs that row rather
    /// than the line — so the instruction says plainly what a number is.
    ///
    /// The literal word JSON is in it on purpose: it is the only hint a chat-tuned local
    /// model gets about the shape, and it is cheap insurance for a server that quietly
    /// wants to see the word before it will answer with one object.
    static let answerShape = """
        Answer with one JSON object and nothing else: no explanation, no code fence. The object has exactly these keys:
        {"items": [{"name": "string", "candidate": number, "grams": number, "certainty": "certain" or "probable" or "unsure", "implausible": true or false}], "meal": "breakfast" or "lunch" or "dinner" or "snack", "note": "string"}
        candidate is the id of a row one of the searches returned, or 0 when neither search holds that food.
        grams is a plain number of grams, between 1 and 3000, not a string and not a range. List at most 12 items.
        """

    // MARK: - Request

    /// What to send for this input, or a failure the user can act on.
    ///
    /// The photo switch is honoured here rather than in the loop, so that "a photo was
    /// not sent" is a decision one test can pin down. When photos are off and words came
    /// with the picture, those words are sent as an ordinary description: asking about
    /// "the attached photo" when nothing is attached invites the model to invent what it
    /// cannot see.
    static func content(for input: EstimationInput, sendsPhotos: Bool) throws -> OpenAICompatibleContent {
        switch input {
        case .text(let line):
            return .text(LinePrompt.text(line: line))
        case .photo(let data, let line):
            guard sendsPhotos else {
                let hint = LinePrompt.clean(line ?? "")
                guard !hint.isEmpty else { throw EstimationError.unavailable(photosNotAllowed) }
                return .text(LinePrompt.text(line: hint))
            }
            guard let dataURL = imageDataURL(for: data) else {
                throw EstimationError.failed(EstimationError.unreadablePhoto)
            }
            return .textAndImage(text: LinePrompt.photo(line: line), dataURL: dataURL)
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

    /// The opening turn: what was written, and the photograph where there is one.
    static func userMessage(_ content: OpenAICompatibleContent) -> JSONValue {
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
        return .object(["role": .string("user"), "content": spoken])
    }

    /// The model's own turn, going back into the next request.
    ///
    /// Rebuilt from the three fields the API documents rather than replayed byte for byte,
    /// which is the opposite of what the Messages API path does — and the difference is in
    /// the protocols rather than in the care taken. There a turn can hold a reasoning
    /// block whose signature belongs to the conversation that produced it, so rebuilding
    /// the turn would be an edit to the history. Chat completions has nothing of the kind;
    /// what it has instead is servers that add fields of their own to a reply and then
    /// refuse them on the way back in. So the call is kept exactly — id, name, and the
    /// arguments string as it arrived — and whatever else came with it is not sent.
    static func assistantTurn(content: String?, calls: [ToolCall]) -> JSONValue {
        var turn: [String: JSONValue] = [
            "role": .string("assistant"),
            "tool_calls": .array(calls.map(self.call)),
        ]
        // An absent content is an absent key rather than a null. A null is what the API
        // itself answers with beside a tool call, and more than one compatible server
        // rejects one arriving.
        if let content, !content.isEmpty { turn["content"] = .string(content) }
        return .object(turn)
    }

    /// One call of a replayed turn.
    static func call(_ call: ToolCall) -> JSONValue {
        .object([
            "id": .string(call.id),
            "type": .string("function"),
            "function": .object([
                "name": .string(call.tool),
                "arguments": .string(call.arguments),
            ]),
        ])
    }

    /// One search's answer, against the call it answers. Every call in a replayed turn has
    /// to be followed by a message carrying its id, including the ones this app cannot
    /// run: a call left unanswered makes the next request invalid.
    ///
    /// There is no `is_error` here, unlike the Messages API's tool result, so a failure is
    /// said in the words the model reads and nowhere else.
    static func toolResult(id: String, text: String) -> JSONValue {
        .object([
            "role": .string("tool"),
            "tool_call_id": .string(id),
            "content": .string(text),
        ])
    }

    /// The JSON body of one chat-completions request. `messages` is the whole conversation
    /// so far: the endpoint keeps nothing between calls, so a tool loop resends what it
    /// has.
    ///
    /// Throws rather than sending an empty model, which is a second defence behind
    /// `RemoteEstimatorSettings.isUsable`: a caller that lost the model field gets a
    /// sentence naming it instead of a 400 the user cannot connect to anything they typed.
    static func body(model: String, messages: [JSONValue], searchesProducts: Bool) throws -> Data {
        let named = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else {
            throw EstimationError.unavailable("Add the model your endpoint serves in Settings.")
        }
        let request: JSONValue = .object([
            "model": .string(named),
            "messages": .array(messages),
            "tools": .array(tools(searchesProducts: searchesProducts)),
        ])
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw EstimationError.failed("the request could not be built.")
        }
    }

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

    /// The tools, in a fixed order so the request prefix is stable between rounds.
    static func tools(searchesProducts: Bool) -> [JSONValue] {
        var tools = [
            tool(
                named: LinePrompt.foodTool, description: LinePrompt.foodToolDescription,
                term: "A food to look for, in whatever wording you want to try"
            )
        ]
        if searchesProducts {
            tools.append(
                tool(
                    named: LinePrompt.productTool, description: LinePrompt.productToolDescription,
                    term: "A product name or brand to look for"
                )
            )
        }
        return tools
    }

    /// One tool, as the request declares it: every search takes the one argument.
    ///
    /// No `strict` flag, unlike the Messages API path. There it makes reading `input.term`
    /// safe without a fallback for every shape; here the fallback exists anyway, because
    /// the arguments arrive as a string a model wrote and a missing term has to read as an
    /// empty search rather than as a dropped call. So the flag would buy nothing and is
    /// one more key for a server to object to.
    static func tool(named name: String, description: String, term: String) -> JSONValue {
        .object([
            "type": .string("function"),
            "function": .object([
                "name": .string(name),
                "description": .string(description),
                "parameters": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("term")]),
                    "properties": .object(["term": JSONSchema.field("string", term)]),
                ]),
            ]),
        ])
    }

    // MARK: - Response

    /// What one reply says to do next.
    nonisolated enum Step: Hashable, Sendable {
        /// Searches to run here, with the turn to replay so the calls can be answered.
        case searches(turn: JSONValue, calls: [ToolCall])
        /// The line, resolved.
        case answer(ResolvedLine)
    }

    /// One search the model asked for. `tool` is whatever name came back rather than a
    /// case of an enum, so a name this app does not know can be answered with a sentence
    /// instead of being dropped — a dropped call leaves the next request invalid.
    nonisolated struct ToolCall: Hashable, Sendable {
        let id: String
        let tool: String
        let term: String
        /// The arguments as they arrived, carried so the replayed turn sends the model its
        /// own words back rather than a re-encoding of what this app read out of them.
        let arguments: String
    }

    /// The reply, read. Throws `EstimationError` for anything that cannot continue.
    static func step(from data: Data) throws -> Step {
        let reply: RemoteCompletionResponse
        do {
            reply = try JSONDecoder().decode(RemoteCompletionResponse.self, from: data)
        } catch {
            throw EstimationError.failed(unreadableAnswer)
        }
        // A model that declines says so in its own field on newer endpoints and in
        // `finish_reason` on the rest; either way it is the same refusal the on-device
        // guardrail produces, and the sheet already has words for that one.
        if let refusal = reply.refusal, !refusal.isEmpty { throw EstimationError.guardrail }
        switch reply.finishReason {
        case "content_filter":
            throw EstimationError.guardrail
        // Read before the content rather than after the content fails to parse: half an
        // object is unreadable for a reason the user can do something about.
        case "length":
            throw EstimationError.failed(cutOff)
        default:
            break
        }

        let calls = reply.toolCalls.compactMap(toolCall)
        if !calls.isEmpty {
            return .searches(
                turn: assistantTurn(content: reply.content, calls: calls), calls: calls
            )
        }
        guard let spoken = reply.content,
              let object = jsonObject(in: spoken),
              let body = object.data(using: .utf8),
              let answer = try? JSONDecoder().decode(ResolvedLine.self, from: body)
        else { throw EstimationError.failed(unreadableAnswer) }
        return .answer(answer)
    }

    /// One `tool_calls` entry as a call, or `nil` when it carries no id or no name — the
    /// two things an answer needs. Such an entry is left out of the replayed turn as well,
    /// which is the point of reading the calls and the turn from the same list: every call
    /// that goes back out is one this app can answer.
    private static func toolCall(_ call: JSONValue) -> ToolCall? {
        guard let id = call["id"]?.stringValue,
              let function = call["function"],
              let name = function["name"]?.stringValue
        else { return nil }
        let arguments = function["arguments"]
        return ToolCall(
            id: id, tool: name, term: term(in: arguments), arguments: written(arguments)
        )
    }

    /// The term a call asks for.
    ///
    /// The arguments are JSON *inside a string*, so they are parsed rather than searched.
    /// Matching on the text would be the shorter thing to write and wrong for the first
    /// term containing a brace, a quote or an escape — and this is the one field of the
    /// request a model writes freely.
    ///
    /// A missing or unreadable term is an empty one rather than a dropped call: the call
    /// still has to be answered, and a search for nothing answers with nothing.
    static func term(in arguments: JSONValue?) -> String {
        guard let arguments else { return "" }
        guard let written = arguments.stringValue else {
            // A few servers send the arguments as an object rather than as the string the
            // API documents. Read that too: it is a difference that costs nothing to
            // accept and a whole round trip to reject.
            return arguments["term"]?.stringValue ?? ""
        }
        guard let data = written.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return "" }
        return value["term"]?.stringValue ?? ""
    }

    /// The arguments as they go back out: the string the API documents, which is what
    /// arrived except from the servers that send an object instead.
    static func written(_ arguments: JSONValue?) -> String {
        if let text = arguments?.stringValue { return text }
        guard let arguments, let data = try? JSONEncoder().encode(arguments) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The outermost braced object in a reply, or `nil` when there is none.
    ///
    /// Only a server that honours a schema returns bare JSON, and this path sends none.
    /// Everything else wraps it: a chat-tuned model fences it as ```json, puts "Here is
    /// the answer:" in front of it, or adds a closing remark after it. The first brace to
    /// the last one is the answer and the rest is conversation, which also disposes of the
    /// fence without having to recognise one.
    static func jsonObject(in reply: String) -> String? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(reply[start...end])
    }

    // MARK: - Failures

    /// Words a server uses when it cannot do anything with the tools in the request.
    static let toolRejectionMarkers = [
        "tools", "tool_calls", "tool calls", "tool_choice", "function call", "function_call",
        "function calling", "functions",
    ]

    /// Statuses that say nothing about what was in the request, so a word about tools in
    /// one of their bodies is a coincidence rather than a diagnosis.
    static let statusesNotAboutTheRequest = [401, 403, 408, 429]

    /// Whether a rejection reads like the endpoint refusing to call tools at all.
    ///
    /// There is no status code for this and no error code either: a server built without
    /// tool support answers 400 (llama.cpp, LM Studio), a 422 naming the offending field
    /// (anything built on FastAPI, vLLM among them) or occasionally a 500 from a proxy in
    /// front of it. The only thing they agree on is that the words appear somewhere in the
    /// body, so the body is what is searched — the same bargain this path made for the
    /// strict schema before, and the same trade in both directions: a false positive names
    /// the wrong limitation, a false negative leaves the user with "the endpoint answered
    /// 400." and nothing to go and fix.
    ///
    /// A server that instead accepts the declaration and quietly ignores it cannot be
    /// told from a model that answered too soon, so nothing here tries. What happens then
    /// is bounded by the pool rather than by a guess: the model never saw a row, so every
    /// candidate it names is an id this request never issued, and every one of those reads
    /// as "none of these" — the line comes back as rows for the user to settle.
    static func rejectsTools(status: Int, body: Data) -> Bool {
        guard !(200..<300).contains(status), !statusesNotAboutTheRequest.contains(status) else {
            return false
        }
        let text = preview(of: body).lowercased()
        return toolRejectionMarkers.contains { text.contains($0) }
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
}

// MARK: - Response bodies

/// What a chat-completions answer is read down to: the first choice's text, the searches
/// it asked for, why it stopped, and the refusal field OpenAI added when a model declines
/// in words.
///
/// The calls are kept as they arrived rather than decoded into a type. What a call is for
/// — an id, a name and a term — is read in `OpenAICompatiblePayload.step(from:)`, which is
/// where the decision about an unanswerable one belongs; the shape here only has to carry
/// them that far without losing the arguments string a model wrote.
nonisolated struct RemoteCompletionResponse: Sendable, Decodable {
    let content: String?
    /// Lowercased, so "stop", "length", "tool_calls" and "content_filter" can be compared
    /// directly.
    let finishReason: String?
    let refusal: String?
    let toolCalls: [JSONValue]

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
        toolCalls = first?.message?.toolCalls ?? []
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
    let toolCalls: [JSONValue]

    private enum CodingKeys: String, CodingKey {
        case content
        case refusal
        case toolCalls = "tool_calls"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refusal = try? container.decode(String.self, forKey: .refusal)
        toolCalls = (try? container.decode([JSONValue].self, forKey: .toolCalls)) ?? []
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
