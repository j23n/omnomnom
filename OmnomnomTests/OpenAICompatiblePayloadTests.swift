import CoreGraphics
import Foundation
import Testing
@testable import Omnomnom

/// An endpoint that answers a script in order and keeps every request it was given, so a
/// test can assert what the second round trip carried as well as what came back.
///
/// `FakeTransport` answers one reply and is right for a client that makes one request; a
/// loop makes several and the point of testing it is what happens between them. A status
/// per answer, because one of this path's failures is read out of a non-2xx body rather
/// than out of the status alone.
actor EndpointScript: HTTPTransport {
    private var answers: [(status: Int, body: String)]
    private(set) var bodies: [Data] = []

    /// Every answer a 200, which is what all but the failures want.
    init(_ replies: [String]) {
        answers = replies.map { (status: 200, body: $0) }
    }

    init(status: Int, body: String) {
        answers = [(status: status, body: body)]
    }

    var rounds: Int { bodies.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        bodies.append(request.httpBody ?? Data())
        guard let url = request.url, !answers.isEmpty else { throw URLError(.badServerResponse) }
        let answer = answers.removeFirst()
        guard let response = HTTPURLResponse(
            url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil
        ) else { throw URLError(.badServerResponse) }
        return (Data(answer.body.utf8), response)
    }
}

/// Searches that answer from a script and record what they were asked, standing in for the
/// device's own tables and for Open Food Facts.
@MainActor
final class EndpointSearches: LineSearching {
    var foodHits: [String: [FoodMatch]] = [:]
    var productHits: [String: [ProductRecord]] = [:]
    var searchesProducts = true
    private(set) var foodTerms: [String] = []
    private(set) var productTerms: [String] = []

    func foods(matching term: String) async -> [FoodMatch] {
        foodTerms.append(term)
        return foodHits[term] ?? []
    }

    func products(matching term: String) async -> [ProductRecord] {
        productTerms.append(term)
        return productHits[term] ?? []
    }
}

/// What this path asks an OpenAI-compatible endpoint for, what it makes of the answer, and
/// the loop between the two — all of it without a network.
///
/// The replies here are the shapes real servers send: a tool call whose arguments are JSON
/// inside a string, a message with fields of the server's own alongside the call, an answer
/// fenced as markdown, a reply cut off at the token limit.
@MainActor
struct OpenAICompatiblePayloadTests {
    // MARK: - Helpers

    /// One request's body, as JSON. Parsed here rather than inside the transport, because
    /// a dictionary of `Any` is not sendable and has no business crossing out of an actor.
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sentMessages(in body: Data) throws -> [[String: Any]] {
        try #require(try object(body)["messages"] as? [[String: Any]])
    }

    private func settings() -> RemoteEstimatorSettings {
        RemoteEstimatorSettings(baseURL: "https://example.invalid/v1", model: "llama3.1")
    }

    private func match(_ id: Int, _ name: String, kcal: Double = 370, ingredient: Bool = false) -> FoodMatch {
        FoodMatch(
            food: BundledFood(
                id: id, name: name, category: "cereals", per100g: Nutrition(energy: kcal),
                popularity: 0, isIngredient: ingredient
            ),
            score: 0.8
        )
    }

    private func product(_ code: String, _ name: String, brand: String? = nil) -> ProductRecord {
        ProductRecord(
            code: code, name: name, brand: brand,
            per100g: Nutrition(energy: 400, protein: 8, carbohydrates: 60, fatTotal: 12)
        )
    }

    /// A reply that asks for one search. Raw so the arguments can be written as what they
    /// are: JSON inside a JSON string.
    private func searchReply(
        id: String = "call_1", term: String, tool: String = "search_foods"
    ) -> String {
        #"""
        {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
          {"id":"\#(id)","type":"function","function":{"name":"\#(tool)","arguments":"{\"term\":\"\#(term)\"}"}}
        ]},"finish_reason":"tool_calls"}]}
        """#
    }

    /// A reply that answers with one item.
    private func answerReply(
        candidate: Int, grams: Double = 45, certainty: String = "certain", meal: String = "breakfast"
    ) -> String {
        let item = #"""
            {\"name\":\"oats\",\"candidate\":\#(candidate),\"grams\":\#(grams),\"certainty\":\"\#(certainty)\",\"implausible\":false}
            """#
        return #"""
            {"choices":[{"message":{"role":"assistant","content":"{\"items\":[\#(item)],\"meal\":\"\#(meal)\",\"note\":\"\"}"},"finish_reason":"stop"}]}
            """#
    }

    private func resolver(
        _ replies: [String], searcher: EndpointSearches
    ) -> (OpenAICompatibleLineResolver, EndpointScript) {
        let transport = EndpointScript(replies)
        return (
            OpenAICompatibleLineResolver(
                settings: settings(), key: "sk-test", searcher: searcher, transport: transport
            ),
            transport
        )
    }

    private func body(
        model: String = "llama3.1", products: Bool = false, messages: [JSONValue]? = nil
    ) throws -> [String: Any] {
        let sent = messages ?? [
            OpenAICompatiblePayload.systemMessage,
            OpenAICompatiblePayload.userMessage(.text("two eggs")),
        ]
        return try object(
            try OpenAICompatiblePayload.body(model: model, messages: sent, searchesProducts: products)
        )
    }

    // MARK: - The request

    @Test func theRequestCarriesTheModelTheInstructionsAndTheWords() throws {
        let root = try body(model: "  llama3.1  ")
        #expect(root["model"] as? String == "llama3.1")
        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        // The instructions are a message here, not the field the Messages API takes.
        #expect(messages[0]["role"] as? String == "system")
        let system = try #require(messages[0]["content"] as? String)
        #expect(system.hasPrefix(LinePrompt.instructions))
        #expect(messages[1]["role"] as? String == "user")
        #expect((messages[1]["content"] as? String)?.contains("two eggs") == true)
    }

    @Test func theShapeOfTheAnswerIsStatedInWordsBecauseNoSchemaIsSent() throws {
        // The one capability this request asks for is tools. A strict schema beside them is
        // the pair a self-hosted server is likeliest to refuse, and there is no second,
        // plainer attempt any more to absorb a refusal.
        let root = try body()
        #expect(root.keys.contains("response_format") == false)
        // Sending 0 bought determinism and cost a hard 400 on a reasoning model that will
        // not take one.
        #expect(root.keys.contains("temperature") == false)
        let system = try #require((root["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(system.contains("JSON"))
        #expect(system.contains("candidate"))
        #expect(system.contains("certainty"))
        // The grams sentence is load-bearing: a weight written as words decodes to no
        // weight at all, which costs that row.
        #expect(system.contains("3000"))
        #expect(system.contains("not a string"))
    }

    @Test func theToolsAreDeclaredInTheShapeChatCompletionsTakes() throws {
        let tools = try #require(try body()["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        let function = try #require(tools[0]["function"] as? [String: Any])
        #expect(function["name"] as? String == LinePrompt.foodTool)
        #expect((function["description"] as? String) == LinePrompt.foodToolDescription)
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["required"] as? [String] == ["term"])
        #expect(parameters["additionalProperties"] as? Bool == false)
        #expect((parameters["properties"] as? [String: Any])?.keys.contains("term") == true)
        // No `strict`: the term is read tolerantly anyway, so the flag would buy nothing
        // and is one more key for a server to object to.
        #expect(function.keys.contains("strict") == false)
    }

    @Test func theProductSearchIsDeclaredOnlyBehindItsOptIn() throws {
        let without = try #require(try body(products: false)["tools"] as? [[String: Any]])
        #expect(without.map { ($0["function"] as? [String: Any])?["name"] as? String }
            == [LinePrompt.foodTool])

        let with = try #require(try body(products: true)["tools"] as? [[String: Any]])
        // An undeclared tool cannot be called, which is not the same as one that answers
        // nothing: the model never spends a round trip discovering it is empty.
        #expect(with.map { ($0["function"] as? [String: Any])?["name"] as? String }
            == [LinePrompt.foodTool, LinePrompt.productTool])
    }

    @Test func anEmptyModelIsRefusedBeforeItReachesTheEndpoint() {
        // A second defence behind `isUsable`: a sentence naming the field beats a 400 the
        // user cannot connect to anything they typed.
        #expect(throws: EstimationError.self) {
            try OpenAICompatiblePayload.body(model: "   ", messages: [], searchesProducts: false)
        }
    }

    @Test func theKeyBecomesABearerHeaderAndAMissingOneBecomesNoHeader() throws {
        let url = try #require(URL(string: "https://example.invalid/v1/chat/completions"))
        let body = Data(#"{"model":"m"}"#.utf8)
        let signed = OpenAICompatiblePayload.request(url: url, key: " sk-test ", body: body)
        #expect(signed.httpMethod == "POST")
        #expect(signed.httpBody == body)
        #expect(signed.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(signed.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(signed.timeoutInterval == OpenAICompatiblePayload.timeout)
        // A server that needs no key must not be sent an empty bearer.
        #expect(OpenAICompatiblePayload.request(url: url, key: nil, body: body)
            .value(forHTTPHeaderField: "Authorization") == nil)
        #expect(OpenAICompatiblePayload.request(url: url, key: "   ", body: body)
            .value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Photos

    @Test func thePhotoTravelsAsADataURLOnlyWhenPhotosAreAllowed() throws {
        let png = try #require(Fixtures.pngData(width: 40, height: 30))
        let allowed = try OpenAICompatiblePayload.content(
            for: .photo(png, description: "half of it left"), sendsPhotos: true
        )
        let message = try object(
            try JSONEncoder().encode(OpenAICompatiblePayload.userMessage(allowed))
        )
        let parts = try #require(message["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect((parts[0]["text"] as? String)?.contains("attached photo") == true)
        #expect(parts[1]["type"] as? String == "image_url")
        let dataURL = try #require((parts[1]["image_url"] as? [String: Any])?["url"] as? String)
        #expect(dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(dataURL.count > "data:image/jpeg;base64,".count)
    }

    @Test func wordsGoAloneWhenThePhotoMayNotBeSent() throws {
        let png = try #require(Fixtures.pngData(width: 40, height: 30))
        let refused = try OpenAICompatiblePayload.content(
            for: .photo(png, description: "half of it left"), sendsPhotos: false
        )
        let message = try object(
            try JSONEncoder().encode(OpenAICompatiblePayload.userMessage(refused))
        )
        let spoken = try #require(message["content"] as? String)
        #expect(spoken.contains("half of it left"))
        #expect(!spoken.contains("data:image"))
        // Nothing is attached, so nothing may invite the model to describe a photograph.
        #expect(!spoken.contains("photo"))
    }

    @Test func aPhotoWithNoWordsIsRefusedWhenPhotosMayNotBeSent() throws {
        let png = try #require(Fixtures.pngData(width: 20, height: 20))
        #expect(throws: EstimationError.unavailable(OpenAICompatiblePayload.photosNotAllowed)) {
            try OpenAICompatiblePayload.content(for: .photo(png, description: "   "), sendsPhotos: false)
        }
        #expect(throws: EstimationError.unavailable(OpenAICompatiblePayload.photosNotAllowed)) {
            try OpenAICompatiblePayload.content(for: .photo(png, description: nil), sendsPhotos: false)
        }
    }

    @Test func bytesThatAreNotAnImageAreRefusedBeforeAnythingIsSent() {
        #expect(throws: EstimationError.self) {
            try OpenAICompatiblePayload.content(for: .photo(Data("nope".utf8), description: nil), sendsPhotos: true)
        }
    }

    @Test func aLargePhotoIsDownscaledBeforeItIsEncoded() throws {
        let png = try #require(Fixtures.pngData(width: 2400, height: 1800))
        let dataURL = try #require(OpenAICompatiblePayload.imageDataURL(for: png))
        let encoded = try #require(dataURL.split(separator: ",", maxSplits: 1).last.map(String.init))
        let jpeg = try #require(Data(base64Encoded: encoded))
        let decoded = try #require(PhotoData.downscaled(jpeg, maxPixelSize: 4096))
        #expect(decoded.width == OpenAICompatiblePayload.imagePixelSize)
        #expect(decoded.height == OpenAICompatiblePayload.imagePixelSize * 3 / 4)
    }

    @Test func aPhotoReachesTheLoopAndALineWithoutOneSendsNoImagePart() async throws {
        let png = try #require(Fixtures.pngData(width: 40, height: 30))
        let searcher = EndpointSearches()
        let seeing = EndpointScript([answerReply(candidate: 0)])
        let subject = OpenAICompatibleLineResolver(
            settings: RemoteEstimatorSettings(
                baseURL: "https://example.invalid/v1", model: "llama3.1", sendsPhotos: true
            ),
            key: "sk-test", searcher: searcher, transport: seeing
        )
        _ = try await subject.resolve(.photo(png, description: "porridge"))
        let withPhoto = try sentMessages(in: await seeing.bodies[0])
        let parts = try #require(withPhoto.last?["content"] as? [[String: Any]])
        #expect(parts.map { $0["type"] as? String } == ["text", "image_url"])

        // The switch is its own, and off by default, so the same photo goes as the words
        // that came with it and nothing else.
        let quiet = EndpointScript([answerReply(candidate: 0)])
        let silent = OpenAICompatibleLineResolver(
            settings: settings(), key: "sk-test", searcher: searcher, transport: quiet
        )
        _ = try await silent.resolve(.photo(png, description: "porridge"))
        let withoutPhoto = try sentMessages(in: await quiet.bodies[0])
        let spoken = try #require(withoutPhoto.last?["content"] as? String)
        #expect(spoken.contains("porridge"))
        #expect(!spoken.contains("data:image"))
    }

    // MARK: - Reading the reply

    @Test func toolArgumentsAreParsedAsJSONRatherThanMatchedAsText() throws {
        // The arguments arrive as JSON inside a string, so they are parsed. Matching on the
        // text is shorter to write and wrong for the first term holding a brace, a quote or
        // an escape — and the term is the one field of the request a model writes freely.
        let awkward = #"{"note":"term is not a key here","term":"oat \"milk\", {half} fat"}"#
        #expect(OpenAICompatiblePayload.term(in: .string(awkward)) == #"oat "milk", {half} fat"#)
        // Key order and whitespace are the model's to choose.
        #expect(OpenAICompatiblePayload.term(in: .string(#"{ "term" : "rolled oats" }"#)) == "rolled oats")
        // A few servers send the object itself rather than the string the API documents.
        #expect(OpenAICompatiblePayload.term(in: .object(["term": .string("oats")])) == "oats")
        // A missing or unreadable term is an empty search, never a dropped call: a call
        // left unanswered makes the next request invalid.
        #expect(OpenAICompatiblePayload.term(in: .string("{}")) == "")
        #expect(OpenAICompatiblePayload.term(in: .string("not json at all")) == "")
        #expect(OpenAICompatiblePayload.term(in: nil) == "")
    }

    @Test func aCallBecomesASearchAndTheTurnItCameInGoesBackWithIt() throws {
        let step = try OpenAICompatiblePayload.step(from: Data(searchReply(term: "rolled oats").utf8))
        guard case .searches(let turn, let calls) = step else {
            Issue.record("expected searches, got \(step)")
            return
        }
        #expect(calls.map(\.id) == ["call_1"])
        #expect(calls.map(\.tool) == [LinePrompt.foodTool])
        #expect(calls.map(\.term) == ["rolled oats"])
        #expect(turn["role"]?.stringValue == "assistant")
        // An absent content is an absent key rather than a null: a null is what the API
        // answers with beside a call, and more than one server rejects one arriving.
        #expect(turn["content"] == nil)
        let replayed = try #require(turn["tool_calls"]?.arrayValue)
        #expect(replayed.count == 1)
        #expect(replayed[0]["id"]?.stringValue == "call_1")
        #expect(replayed[0]["type"]?.stringValue == "function")
        // The arguments go back as the string they arrived as, not as a re-encoding of
        // what this app read out of them.
        #expect(replayed[0]["function"]?["arguments"]?.stringValue == #"{"term":"rolled oats"}"#)
    }

    @Test func whatTheServerAddedToItsOwnReplyIsNotSentBackToIt() throws {
        // The opposite of what the Messages API path does, and the difference is in the
        // protocols: there a turn can hold a reasoning block whose signature belongs to the
        // conversation, so it is replayed byte for byte. Here there is no such thing, and
        // what there is instead is servers that add fields to a reply and refuse them on
        // the way back in.
        let reply = #"""
            {"choices":[{"message":{"role":"assistant","content":"searching","reasoning_content":"thought",
              "tool_calls":[{"index":0,"id":"call_1","type":"function",
              "function":{"name":"search_foods","arguments":"{\"term\":\"oats\"}"}}]},"finish_reason":"tool_calls"}]}
            """#
        guard case .searches(let turn, _) = try OpenAICompatiblePayload.step(from: Data(reply.utf8)) else {
            Issue.record("expected searches")
            return
        }
        let keys = try #require(turn.objectValue?.keys).sorted()
        #expect(keys == ["content", "role", "tool_calls"])
        #expect(turn["content"]?.stringValue == "searching")
        let call = try #require(turn["tool_calls"]?.arrayValue?.first?.objectValue)
        #expect(call.keys.sorted() == ["function", "id", "type"])
        let function = try #require(call["function"]?.objectValue)
        #expect(function.keys.sorted() == ["arguments", "name"])
    }

    @Test func aCallThisAppHasNoToolForIsStillACallWithAnID() throws {
        let step = try OpenAICompatiblePayload.step(from: Data(#"""
            {"choices":[{"message":{"tool_calls":[
              {"id":"call_9","type":"function","function":{"name":"search_the_web","arguments":""}}
            ]},"finish_reason":"tool_calls"}]}
            """#.utf8))
        guard case .searches(_, let calls) = step else {
            Issue.record("expected searches, got \(step)")
            return
        }
        #expect(calls.first?.tool == "search_the_web")
        #expect(calls.first?.term == "")
    }

    @Test func anEntryWithNoIDIsNeitherAnsweredNorReplayed() throws {
        // Read from one list on purpose: a call that cannot be answered must not go back
        // out either, or the next request is invalid for a call nothing can reply to.
        let step = try OpenAICompatiblePayload.step(from: Data(#"""
            {"choices":[{"message":{"tool_calls":[
              {"type":"function","function":{"name":"search_foods","arguments":"{\"term\":\"oats\"}"}},
              {"id":"call_2","type":"function","function":{"name":"search_foods","arguments":"{\"term\":\"toast\"}"}}
            ]},"finish_reason":"tool_calls"}]}
            """#.utf8))
        guard case .searches(let turn, let calls) = step else {
            Issue.record("expected searches, got \(step)")
            return
        }
        #expect(calls.map(\.id) == ["call_2"])
        #expect(turn["tool_calls"]?.arrayValue?.count == 1)
    }

    @Test func theAnswerIsReadFromTheFirstChoicesText() throws {
        guard case .answer(let answer) = try OpenAICompatiblePayload.step(
            from: Data(answerReply(candidate: 3, grams: 60, meal: "lunch").utf8)
        ) else {
            Issue.record("expected an answer")
            return
        }
        #expect(answer.items.count == 1)
        #expect(answer.items.first?.candidate == 3)
        #expect(answer.items.first?.grams == 60)
        #expect(answer.items.first?.certainty == .certain)
        #expect(answer.meal == .lunch)
    }

    @Test func anAnswerWrappedInConversationIsStillRead() throws {
        // No schema is sent, so nothing makes a reply bare. A chat-tuned model fences it,
        // prefaces it, or adds a closing remark; the first brace to the last one is the
        // answer and the rest is talk.
        let fenced = #"""
            {"choices":[{"message":{"content":"Here you go:\n```json\n{\"items\":[],\"meal\":\"dinner\",\"note\":\"\"}\n```\nHope that helps."},"finish_reason":"stop"}]}
            """#
        guard case .answer(let answer) = try OpenAICompatiblePayload.step(from: Data(fenced.utf8)) else {
            Issue.record("expected an answer")
            return
        }
        #expect(answer.meal == .dinner)
        #expect(answer.items.isEmpty)
    }

    @Test func aRefusalIsTheGuardrailTheSheetAlreadyHasWordsFor() {
        let refused = #"{"choices":[{"message":{"content":null,"refusal":"I can't help with that."},"finish_reason":"stop"}]}"#
        #expect(throws: EstimationError.guardrail) {
            try OpenAICompatiblePayload.step(from: Data(refused.utf8))
        }
        let filtered = #"{"choices":[{"message":{"content":""},"finish_reason":"content_filter"}]}"#
        #expect(throws: EstimationError.guardrail) {
            try OpenAICompatiblePayload.step(from: Data(filtered.utf8))
        }
    }

    @Test func beingCutOffSaysSoRatherThanReadingAsNonsense() {
        // Half a JSON object fails to parse for a reason the user can act on — and on a
        // server they run themselves, one they can go and change.
        let cut = #"{"choices":[{"message":{"content":"{\"items\":[{"},"finish_reason":"length"}]}"#
        #expect(throws: EstimationError.failed(OpenAICompatiblePayload.cutOff)) {
            try OpenAICompatiblePayload.step(from: Data(cut.utf8))
        }
    }

    @Test func aReplyWithNeitherACallNorAnAnswerIsUnreadable() {
        for reply in [
            #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":"I'm sorry, I can't help with that."}}]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            "not json at all",
        ] {
            #expect(throws: EstimationError.failed(OpenAICompatiblePayload.unreadableAnswer)) {
                try OpenAICompatiblePayload.step(from: Data(reply.utf8))
            }
        }
    }

    // MARK: - The loop

    @Test func aSearchIsRunHereAndItsRowsGoBackAgainstTheCallTheyAnswer() async throws {
        let searcher = EndpointSearches()
        searcher.foodHits["rolled oats"] = [match(1, "Oat flakes")]
        let (subject, transport) = resolver(
            [searchReply(term: "rolled oats"), answerReply(candidate: 1)], searcher: searcher
        )
        let driven = try await subject.resolve(.text("oats"))

        #expect(searcher.foodTerms == ["rolled oats"])
        let rounds = await transport.rounds
        #expect(rounds == 2)
        #expect(driven.answer.items.first?.candidate == 1)
        #expect(driven.pool.candidate(id: 1)?.name == "Oat flakes")

        // The second request replays the turn and answers the call by its id. A call left
        // without a tool message carrying its id makes the request invalid.
        let messages = try sentMessages(in: await transport.bodies[1])
        #expect(messages.count == 4)
        #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "tool"])
        let replayed = try #require(messages[2]["tool_calls"] as? [[String: Any]])
        #expect(replayed.first?["id"] as? String == "call_1")
        #expect(messages[3]["tool_call_id"] as? String == "call_1")
        #expect((messages[3]["content"] as? String)?.contains("id 1: Oat flakes") == true)
    }

    @Test func aSearchThatFoundNothingSaysSoRatherThanAnsweringBlank() async throws {
        // "Nothing" is information worth acting on, and a blank result invites a model to
        // assume the call failed and spend a round trip repeating it.
        let searcher = EndpointSearches()
        let (subject, transport) = resolver(
            [searchReply(term: "unobtainium"), answerReply(candidate: 0)], searcher: searcher
        )
        _ = try await subject.resolve(.text("unobtainium"))
        let messages = try sentMessages(in: await transport.bodies[1])
        #expect((messages[3]["content"] as? String)?.contains("No rows match") == true)
    }

    @Test func idsAreOneSequenceOverBothSearches() async throws {
        // Two sources with no shared namespace, so the ids are this request's own. That is
        // what lets a product be named at all, and what makes the guard one comparison.
        let searcher = EndpointSearches()
        searcher.foodHits["oats"] = [match(1, "Oat flakes"), match(2, "Biscuits, oat")]
        searcher.productHits["oatly"] = [product("7394376615955", "Oatly Oat Drink", brand: "Oatly")]
        let both = #"""
            {"choices":[{"message":{"tool_calls":[
              {"id":"call_1","type":"function","function":{"name":"search_foods","arguments":"{\"term\":\"oats\"}"}},
              {"id":"call_2","type":"function","function":{"name":"search_products","arguments":"{\"term\":\"oatly\"}"}}
            ]},"finish_reason":"tool_calls"}]}
            """#
        let (subject, transport) = resolver([both, answerReply(candidate: 3)], searcher: searcher)
        let driven = try await subject.resolve(.text("oats and oatly"))

        #expect(driven.pool.count == 3)
        #expect(driven.pool.candidate(id: 1)?.name == "Oat flakes")
        #expect(driven.pool.candidate(id: 2)?.name == "Biscuits, oat")
        let third = try #require(driven.pool.candidate(id: 3))
        #expect(third.name == "Oatly Oat Drink")
        #expect(third.isProduct)
        #expect(third.pick == .product(code: "7394376615955"))
        // One message per call, in the order the calls came in.
        let messages = try sentMessages(in: await transport.bodies[1])
        #expect(messages.count == 5)
        #expect(messages[3]["tool_call_id"] as? String == "call_1")
        #expect(messages[4]["tool_call_id"] as? String == "call_2")
    }

    @Test func withTheOptInOffTheProductSearchIsNeitherOfferedNorRun() async throws {
        let searcher = EndpointSearches()
        searcher.searchesProducts = false
        searcher.productHits["oatly"] = [product("1", "Oatly Oat Drink")]
        let (subject, transport) = resolver(
            [searchReply(term: "oatly", tool: "search_products"), answerReply(candidate: 0)],
            searcher: searcher
        )
        _ = try await subject.resolve(.text("oatly"))

        // Not declared, so a model should not ask — and if it does anyway, nothing leaves
        // the device and the call is answered rather than dropped.
        let tools = try #require(try object(await transport.bodies[0])["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(searcher.productTerms.isEmpty)
        let messages = try sentMessages(in: await transport.bodies[1])
        #expect(messages[3]["tool_call_id"] as? String == "call_1")
        // No `is_error` in this protocol, so the sentence carries it.
        #expect((messages[3]["content"] as? String)?.contains("no such search") == true)
    }

    @Test func anIDOutsideThePoolIsNoneOfTheseExactlyAsZeroIs() async throws {
        let searcher = EndpointSearches()
        searcher.foodHits["oats"] = [match(1, "Oat flakes")]
        let (subject, _) = resolver(
            [searchReply(term: "oats"), answerReply(candidate: 99)], searcher: searcher
        )
        let driven = try await subject.resolve(.text("oats"))
        // The model can name a row nobody expected and still cannot name a row nobody
        // found: an id this request never issued reads as "none of these", as 0 does.
        #expect(driven.answer.items.first?.candidate == 99)
        #expect(driven.pool.count == 1)
        #expect(driven.pool.candidate(id: 99) == nil)
        #expect(driven.pool.candidate(id: 0) == nil)
    }

    @Test func aModelThatKeepsSearchingIsStoppedAtTheRoundLimit() async throws {
        let searcher = EndpointSearches()
        let forever = Array(
            repeating: searchReply(term: "oats"), count: LinePrompt.maximumRounds
        )
        let (subject, transport) = resolver(forever, searcher: searcher)
        await #expect(throws: EstimationError.failed(LinePrompt.keptSearching)) {
            try await subject.resolve(.text("oats"))
        }
        // Bounded: a model that will not answer costs a fixed number of requests.
        let rounds = await transport.rounds
        #expect(rounds == LinePrompt.maximumRounds)
    }

    @Test func anUnconfiguredEndpointSaysWhatIsMissingRatherThanFailing() async throws {
        let searcher = EndpointSearches()
        for settings in [
            RemoteEstimatorSettings(baseURL: "not a url at all", model: "m"),
            RemoteEstimatorSettings(baseURL: "https://example.invalid/v1", model: "  "),
        ] {
            let subject = OpenAICompatibleLineResolver(
                settings: settings, key: nil, searcher: searcher, transport: EndpointScript([])
            )
            await #expect(throws: EstimationError.self) {
                try await subject.resolve(.text("oats"))
            }
        }
    }

    // MARK: - Failures

    @Test func anEndpointThatWillNotCallToolsSaysSoInWordsThatNameTheFix() async throws {
        // The one failure here that is about the server rather than the request: a server
        // without tool support cannot read a line however it is addressed, so the sentence
        // names the two things that would help instead of quoting a 400 back.
        let searcher = EndpointSearches()
        let transport = EndpointScript(
            status: 400, body: #"{"error":{"message":"this model does not support tools"}}"#
        )
        let subject = OpenAICompatibleLineResolver(
            settings: settings(), key: "sk-test", searcher: searcher, transport: transport
        )
        await #expect(throws: EstimationError.unavailable(OpenAICompatiblePayload.toolsUnsupported)) {
            try await subject.resolve(.text("oats"))
        }
    }

    @Test func aRejectionAboutTheToolsIsToldApartFromOneAboutAnythingElse() {
        let noTools = Data(#"{"error":{"message":"tools is not supported by this model"}}"#.utf8)
        #expect(OpenAICompatiblePayload.rejectsTools(status: 400, body: noTools))
        let fastAPI = Data(#"{"detail":[{"loc":["body","tool_choice"],"msg":"unexpected value"}]}"#.utf8)
        #expect(OpenAICompatiblePayload.rejectsTools(status: 422, body: fastAPI))
        let proxy = Data("500 Internal Server Error: function calling is disabled".utf8)
        #expect(OpenAICompatiblePayload.rejectsTools(status: 500, body: proxy))
        // Auth and rate limits say nothing about what was in the request, so a word about
        // tools in one of their bodies is a coincidence rather than a diagnosis.
        #expect(!OpenAICompatiblePayload.rejectsTools(status: 401, body: noTools))
        #expect(!OpenAICompatiblePayload.rejectsTools(status: 429, body: noTools))
        #expect(!OpenAICompatiblePayload.rejectsTools(status: 200, body: noTools))
        let otherFailure = Data(#"{"error":{"message":"model not found"}}"#.utf8)
        #expect(!OpenAICompatiblePayload.rejectsTools(status: 400, body: otherFailure))
    }

    @Test func eachRejectionBecomesSomethingTheSheetCanSay() {
        #expect(OpenAICompatiblePayload.error(status: 401, body: Data()) == .unavailable(
            "The endpoint refused the API key. Check it in Settings."
        ))
        guard case .unavailable(let address) = OpenAICompatiblePayload.error(status: 404, body: Data()) else {
            Issue.record("expected unavailable for a 404")
            return
        }
        #expect(address.contains("address"))
        #expect(OpenAICompatiblePayload.error(status: 413, body: Data()) == .tooLong)
        #expect(OpenAICompatiblePayload.error(status: 429, body: Data())
            == .failed(EstimationError.rateLimited))
        let tooLong = Data(#"{"error":{"message":"This model's maximum context length is 4096 tokens"}}"#.utf8)
        #expect(OpenAICompatiblePayload.error(status: 400, body: tooLong) == .tooLong)
        let filtered = Data(#"{"error":{"message":"The response was blocked by a content_filter"}}"#.utf8)
        #expect(OpenAICompatiblePayload.error(status: 400, body: filtered) == .guardrail)
    }

    @Test func aServersOwnWordsAreShownWithTheStatus() {
        let mapped = OpenAICompatiblePayload.error(status: 503, body: Data(#"{"error":"upstream is down"}"#.utf8))
        guard case .failed(let message) = mapped else {
            Issue.record("expected failed, got \(mapped)")
            return
        }
        #expect(message.contains("503"))
        #expect(message.contains("upstream is down"))
        guard case .failed(let bare) = OpenAICompatiblePayload.error(status: 500, body: Data()) else {
            Issue.record("expected failed for an empty body")
            return
        }
        #expect(bare.contains("500"))
    }

    @Test func aFailedStatusIsMappedBeforeAnythingIsDecoded() async throws {
        let searcher = EndpointSearches()
        let transport = EndpointScript(status: 401, body: #"{"error":{"message":"bad key"}}"#)
        let subject = OpenAICompatibleLineResolver(
            settings: settings(), key: "sk-wrong", searcher: searcher, transport: transport
        )
        await #expect(throws: EstimationError.unavailable(
            "The endpoint refused the API key. Check it in Settings."
        )) {
            try await subject.resolve(.text("oats"))
        }
    }
}
