import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Omnomnom

/// The request this app sends and the reading of what comes back, both without a network.
struct AnthropicPayloadTests {
    /// A `width` x `height` image with a flat colour, encoded as PNG through ImageIO.
    private func pngData(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func body(
        messages: [AnthropicMessage], model: String = "claude-opus-5-5", products: Bool = false
    ) throws -> [String: Any] {
        let data = try AnthropicPayload.body(
            model: model, messages: messages, searchesProducts: products
        )
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func reply(_ json: String) -> Data {
        Data(json.utf8)
    }

    // MARK: - The request

    @Test func theRequestCarriesWhatTheMessagesAPIRequires() throws {
        let json = try body(messages: [.user([AnthropicPayload.text("oats")])])
        #expect(json["model"] as? String == "claude-opus-5-5")
        // Required, unlike the OpenAI-compatible path where it is optional and omitted.
        #expect(json["max_tokens"] as? Int == AnthropicPayload.maximumTokens)
        // A field, not a message with a system role.
        #expect(json["system"] as? String == LinePrompt.instructions)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["role"] as? String == "user")
    }

    @Test func nothingIsSentForTemperatureOrThinking() throws {
        // Both are rejected on the current models: temperature outright, and thinking
        // cannot be switched off, so anything sent for it is at best a no-op. The other
        // remote path sends temperature 0 for determinism and this one cannot, which is
        // the one capability the two do not share.
        let json = try body(messages: [.user([AnthropicPayload.text("oats")])])
        #expect(json["temperature"] == nil)
        #expect(json["thinking"] == nil)
    }

    @Test func theAnswersSchemaAndEffortTravelTogether() throws {
        let json = try body(messages: [.user([AnthropicPayload.text("oats")])])
        let output = try #require(json["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == AnthropicPayload.effort)
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        // Strict mode wants these two on every object, and rejects the numeric bounds the
        // grams field would otherwise carry; those are stated in its description instead.
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["items", "meal", "note"])
        let properties = try #require(schema["properties"] as? [String: Any])
        let items = try #require(properties["items"] as? [String: Any])
        let item = try #require(items["items"] as? [String: Any])
        let fields = try #require(item["properties"] as? [String: Any])
        let grams = try #require(fields["grams"] as? [String: Any])
        #expect(grams["minimum"] == nil)
        #expect(grams["maximum"] == nil)
        #expect((grams["description"] as? String)?.contains("between 1 and 3000") == true)
    }

    @Test func theProductSearchIsDeclaredOnlyBehindItsOptIn() throws {
        let without = try body(messages: [.user([])], products: false)
        let one = try #require(without["tools"] as? [[String: Any]])
        #expect(one.map { $0["name"] as? String } == [AnthropicPayload.foodTool])

        let with = try body(messages: [.user([])], products: true)
        let two = try #require(with["tools"] as? [[String: Any]])
        // An undeclared tool cannot be called, which is not the same as one that answers
        // nothing: the model never spends a round trip discovering it is empty.
        #expect(two.map { $0["name"] as? String } == [AnthropicPayload.foodTool, AnthropicPayload.productTool])
        #expect(two.allSatisfy { $0["strict"] as? Bool == true })
        let schema = try #require(two.first?["input_schema"] as? [String: Any])
        #expect(schema["required"] as? [String] == ["term"])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func theKeyGoesInItsOwnHeaderAndTheVersionIsAlwaysSent() throws {
        let url = try #require(URL(string: "https://api.anthropic.com/v1/messages"))
        let request = AnthropicPayload.request(url: url, key: " sk-test ", body: Data())
        #expect(request.httpMethod == "POST")
        // Not a bearer token, which is the one header difference that fails quietly.
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == AnthropicPayload.version)
        #expect(request.timeoutInterval == AnthropicPayload.timeout)
    }

    @Test func withNoKeyNoKeyHeaderIsSent() throws {
        let url = try #require(URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(AnthropicPayload.request(url: url, key: nil, body: Data())
            .value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(AnthropicPayload.request(url: url, key: "  ", body: Data())
            .value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test func aPhotoIsABase64BlockAndComesBeforeTheWords() throws {
        // Not a data: URL, which is the shape the OpenAI-compatible path uses. The order
        // is ours to choose and an image before its text reads better.
        let png = try #require(pngData(width: 400, height: 300))
        let blocks = try AnthropicPayload.opening(
            for: .photo(png, description: "porridge"), sendsPhotos: true
        )
        #expect(blocks.count == 2)
        #expect(blocks.first?["type"]?.stringValue == "image")
        let source = try #require(blocks.first?["source"])
        #expect(source["type"]?.stringValue == "base64")
        #expect(source["media_type"]?.stringValue == "image/jpeg")
        #expect(source["data"]?.stringValue?.isEmpty == false)
        #expect(blocks.last?["type"]?.stringValue == "text")
        #expect(blocks.last?["text"]?.stringValue?.contains("porridge") == true)
    }

    @Test func withPhotosOffTheWordsGoAsAnOrdinaryDescription() throws {
        // Asking about "the attached photo" when nothing is attached invites the model to
        // invent what it cannot see.
        let png = try #require(pngData(width: 400, height: 300))
        let blocks = try AnthropicPayload.opening(
            for: .photo(png, description: "porridge"), sendsPhotos: false
        )
        #expect(blocks.count == 1)
        #expect(blocks.first?["type"]?.stringValue == "text")
        let text = try #require(blocks.first?["text"]?.stringValue)
        #expect(text.contains("porridge"))
        #expect(!text.contains("photo"))
    }

    @Test func aPhotoAloneWithPhotosOffIsRefusedWithSomethingToDo() throws {
        let png = try #require(pngData(width: 400, height: 300))
        #expect(throws: EstimationError.unavailable(AnthropicPayload.photosNotAllowed)) {
            try AnthropicPayload.opening(for: .photo(png, description: nil), sendsPhotos: false)
        }
    }

    @Test func aLargePhotoIsDownscaledBeforeItIsEncoded() throws {
        // Sized for visual tokens rather than for bandwidth: ceil(w/28) x ceil(h/28) of
        // them, and well under the long edge at which the API would downscale it itself.
        let png = try #require(pngData(width: 2400, height: 1800))
        let blocks = try AnthropicPayload.opening(for: .photo(png, description: nil), sendsPhotos: true)
        let encoded = try #require(blocks.first?["source"]?["data"]?.stringValue)
        let jpeg = try #require(Data(base64Encoded: encoded))
        let decoded = try #require(PhotoData.downscaled(jpeg, maxPixelSize: 4096))
        #expect(decoded.width == AnthropicPayload.imagePixelSize)
        #expect(decoded.height == AnthropicPayload.imagePixelSize * 3 / 4)
    }

    // MARK: - Reading the reply

    @Test func toolCallsBecomeSearchesAndTheTurnIsKeptWhole() throws {
        // The turn goes back into the next request as it arrived, reasoning block and all:
        // rebuilding it from the parts this app understands would be an edit to the
        // history, and a model is entitled to refuse one.
        let step = try AnthropicPayload.step(from: reply("""
            {"stop_reason":"tool_use","content":[
              {"type":"thinking","thinking":"","signature":"abc123"},
              {"type":"tool_use","id":"toolu_1","name":"search_foods","input":{"term":"rolled oats"}},
              {"type":"tool_use","id":"toolu_2","name":"search_products","input":{"term":"oatly"}}
            ]}
            """))
        guard case .searches(let turn, let calls) = step else {
            Issue.record("expected searches, got \(step)")
            return
        }
        #expect(turn.count == 3)
        #expect(turn.first?["signature"]?.stringValue == "abc123")
        #expect(calls.map(\.id) == ["toolu_1", "toolu_2"])
        #expect(calls.map(\.tool) == ["search_foods", "search_products"])
        #expect(calls.map(\.term) == ["rolled oats", "oatly"])
    }

    @Test func aCallForAToolThisAppDoesNotHaveIsStillACall() throws {
        // Dropped rather than answered, it would leave the next request invalid: every
        // tool_use needs a tool_result carrying its id.
        let step = try AnthropicPayload.step(from: reply("""
            {"stop_reason":"tool_use","content":[
              {"type":"tool_use","id":"toolu_9","name":"search_the_web","input":{}}
            ]}
            """))
        guard case .searches(_, let calls) = step else {
            Issue.record("expected searches, got \(step)")
            return
        }
        #expect(calls.count == 1)
        #expect(calls.first?.tool == "search_the_web")
        // A missing term is an empty one, not a dropped call.
        #expect(calls.first?.term == "")
    }

    @Test func theFinalTextBlockIsReadAsTheAnswer() throws {
        let step = try AnthropicPayload.step(from: reply("""
            {"stop_reason":"end_turn","content":[{"type":"text","text":"{\\"items\\":[
              {\\"name\\":\\"oats\\",\\"candidate\\":3,\\"grams\\":45,\\"certainty\\":\\"certain\\",\\"implausible\\":false}
            ],\\"meal\\":\\"breakfast\\",\\"note\\":\\"a usual bowl\\"}"}]}
            """))
        guard case .answer(let answer) = step else {
            Issue.record("expected an answer, got \(step)")
            return
        }
        #expect(answer.items.count == 1)
        #expect(answer.items.first?.candidate == 3)
        #expect(answer.items.first?.grams == 45)
        #expect(answer.items.first?.certainty == .certain)
        #expect(answer.meal == .breakfast)
        #expect(answer.note == "a usual bowl")
    }

    @Test func anAnswerWrappedInConversationIsStillRead() throws {
        // Only a reply that honoured the schema is bare JSON. The first brace to the last
        // one is the answer and the rest is talk, which also disposes of a code fence.
        let step = try AnthropicPayload.step(from: reply("""
            {"stop_reason":"end_turn","content":[{"type":"text","text":"Here you go:\\n```json\\n{\\"items\\":[],\\"meal\\":\\"lunch\\",\\"note\\":\\"\\"}\\n```"}]}
            """))
        guard case .answer(let answer) = step else {
            Issue.record("expected an answer, got \(step)")
            return
        }
        #expect(answer.meal == .lunch)
    }

    @Test func aRefusalIsTheGuardrailTheSheetAlreadyHasWordsFor() {
        #expect(throws: EstimationError.guardrail) {
            try AnthropicPayload.step(from: reply(#"{"stop_reason":"refusal","content":[]}"#))
        }
    }

    @Test func beingCutOffMidAnswerSaysSoRatherThanReadingAsNonsense() {
        // Half a JSON object fails to parse for a reason the user can act on, so the stop
        // reason is read before the content rather than after the content fails.
        #expect(throws: EstimationError.failed(AnthropicPayload.cutOff)) {
            try AnthropicPayload.step(from: reply("""
                {"stop_reason":"max_tokens","content":[{"type":"text","text":"{\\"items\\":[{"}]}
                """))
        }
    }

    @Test func aReplyWithNeitherACallNorAnAnswerIsUnreadable() {
        #expect(throws: EstimationError.failed(AnthropicPayload.unreadableAnswer)) {
            try AnthropicPayload.step(from: reply(#"{"stop_reason":"end_turn","content":[]}"#))
        }
        #expect(throws: EstimationError.failed(AnthropicPayload.unreadableAnswer)) {
            try AnthropicPayload.step(from: reply("not json at all"))
        }
    }

    // MARK: - Failures

    @Test func eachStatusBecomesSomethingToGoAndFix() throws {
        let refused = AnthropicPayload.error(status: 401, body: Data())
        guard case .unavailable(let keyMessage) = refused else {
            Issue.record("expected unavailable")
            return
        }
        #expect(keyMessage.contains("key"))

        guard case .unavailable(let addressMessage) = AnthropicPayload.error(status: 404, body: Data()) else {
            Issue.record("expected unavailable")
            return
        }
        #expect(addressMessage.contains("address"))
        #expect(AnthropicPayload.error(status: 413, body: Data()) == .tooLong)
    }

    @Test func theAPIsOwnWordsAreShownBecauseTheyNameTheField() throws {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: must be greater than 0"}}"#.utf8)
        guard case .failed(let message) = AnthropicPayload.error(status: 400, body: body) else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("400"))
        #expect(message.contains("max_tokens"))
    }

    @Test func aBodyInNoShapeThisAppKnowsIsStillShown() throws {
        // The last resort, and the state this path was in when a real 400 arrived: with
        // nothing readable in the envelope there was nothing on screen to say which field
        // the API disliked.
        let body = Data("Bad Request: unexpected field 'thinking' for this model".utf8)
        guard case .failed(let message) = AnthropicPayload.error(status: 400, body: body) else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("unexpected field"))
    }

    @Test func anEmptyBodyLeavesTheStatusToSpeakForItself() throws {
        guard case .failed(let message) = AnthropicPayload.error(status: 500, body: Data()) else {
            Issue.record("expected a failure")
            return
        }
        #expect(message == "the API answered 500.")
    }

    @Test func aPromptThatDidNotFitIsSaidAsLengthRatherThanAsAnError() {
        let body = Data(#"{"error":{"message":"prompt is too long: 1200000 tokens > maximum context length"}}"#.utf8)
        #expect(AnthropicPayload.error(status: 400, body: body) == .tooLong)
    }

    @Test func anOverloadedAPIReadsAsSomethingToRetryRatherThanAFault() throws {
        guard case .failed(let message) = AnthropicPayload.error(status: 529, body: Data()) else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.contains("overloaded"))
    }

    // MARK: - Blocks

    @Test func aToolResultNamesTheCallItAnswers() throws {
        let block = AnthropicPayload.toolResult(id: "toolu_1", text: "id 1: Oat flakes")
        #expect(block["type"]?.stringValue == "tool_result")
        #expect(block["tool_use_id"]?.stringValue == "toolu_1")
        // Absent rather than false, so a successful result carries nothing it need not.
        #expect(block["is_error"] == nil)
        let content = try #require(block["content"]?.arrayValue)
        #expect(content.first?["text"]?.stringValue == "id 1: Oat flakes")
    }

    @Test func anErrorResultSaysSo() {
        let block = AnthropicPayload.toolResult(id: "toolu_1", text: "no such search", isError: true)
        #expect(block["is_error"] == .bool(true))
    }
}
