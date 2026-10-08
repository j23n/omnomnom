import Foundation
import Testing
@testable import Omnomnom

/// The halves of a remote estimate that never touch a network: what is asked for, and what
/// is made of the answer. The answers here are the ones real OpenAI-compatible servers
/// gave: a fenced object, a weight written as a sentence, a missing meal, no items at all.
struct RemoteEstimatePayloadTests {
    private let happyReply = #"{"items":[{"name":"Scrambled eggs","lookupTerm":"scrambled eggs","grams":120},{"name":"Rye toast","lookupTerm":"rye bread","grams":45}],"meal":"breakfast","note":"Assumed two eggs."}"#

    // MARK: - Helpers

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sentMessages(in body: Data) throws -> [[String: Any]] {
        let root = try object(body)
        return try #require(root["messages"] as? [[String: Any]])
    }

    // MARK: - Request

    @Test func theStrictBodyCarriesTheModelTheInstructionsAndTheWords() throws {
        let content = try RemoteEstimatePayload.content(for: .text("two scrambled eggs"), sendsPhotos: false)
        let body = try RemoteEstimatePayload.body(model: "  llama3.1  ", mode: .strict, content: content)
        let root = try object(body)
        #expect(root["model"] as? String == "llama3.1")
        #expect(root["temperature"] as? Double == 0)
        let format = try #require(root["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["name"] as? String == "meal_estimate")
        #expect(schema["strict"] as? Bool == true)
        let messages = try sentMessages(in: body)
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == EstimationPrompt.instructions)
        #expect(messages[1]["role"] as? String == "user")
        let user = try #require(messages[1]["content"] as? String)
        #expect(user.contains("two scrambled eggs"))
    }

    @Test func theSchemaSaysTheShapeWithoutKeywordsStrictModeRefuses() throws {
        let body = try RemoteEstimatePayload.body(model: "m", mode: .strict, content: .text("x"))
        let root = try object(body)
        let format = try #require(root["response_format"] as? [String: Any])
        let schema = try #require(format["json_schema"] as? [String: Any])
        let estimate = try #require(schema["schema"] as? [String: Any])
        #expect(estimate["type"] as? String == "object")
        #expect(estimate["additionalProperties"] as? Bool == false)
        #expect(estimate["required"] as? [String] == ["items", "meal", "note"])
        let properties = try #require(estimate["properties"] as? [String: Any])
        let items = try #require(properties["items"] as? [String: Any])
        #expect(items["type"] as? String == "array")
        // `maxItems` and a numeric `minimum` are both a 400 in OpenAI's strict mode, so
        // the bounds live in the descriptions and in `EstimateConversion` instead.
        #expect(items.keys.contains("maxItems") == false)
        let item = try #require(items["items"] as? [String: Any])
        #expect(item["additionalProperties"] as? Bool == false)
        #expect(item["required"] as? [String] == ["name", "lookupTerm", "grams"])
        let fields = try #require(item["properties"] as? [String: Any])
        let grams = try #require(fields["grams"] as? [String: Any])
        #expect(grams["type"] as? String == "number")
        #expect(grams.keys.contains("minimum") == false)
        #expect((fields["lookupTerm"] as? [String: Any])?["type"] as? String == "string")
        let meal = try #require(properties["meal"] as? [String: Any])
        #expect(meal["enum"] as? [String] == ["breakfast", "lunch", "dinner", "snack"])
    }

    @Test func thePlainBodyAsksOnlyForAJSONObjectAndSaysTheShapeInWords() throws {
        let body = try RemoteEstimatePayload.body(model: "m", mode: .plain, content: .text("one apple"))
        let root = try object(body)
        // A reasoning model that refuses temperature 0 is one reason the plain attempt
        // exists, so the plain attempt cannot send one.
        #expect(root.keys.contains("temperature") == false)
        let format = try #require(root["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_object")
        #expect(format.keys.contains("json_schema") == false)
        let messages = try sentMessages(in: body)
        let system = try #require(messages.first?["content"] as? String)
        #expect(system.hasPrefix(EstimationPrompt.instructions))
        #expect(system.contains("JSON"))
        #expect(system.contains("lookupTerm"))
        #expect(system.contains("3000"))
    }

    @Test func theKeyBecomesABearerHeaderAndAMissingOneBecomesNoHeader() throws {
        let url = try #require(URL(string: "https://example.invalid/v1/chat/completions"))
        let body = Data(#"{"model":"m"}"#.utf8)
        let signed = RemoteEstimatePayload.request(url: url, key: " sk-test ", body: body)
        #expect(signed.httpMethod == "POST")
        #expect(signed.httpBody == body)
        #expect(signed.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(signed.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(signed.timeoutInterval == RemoteEstimatePayload.timeout)
        // A server that needs no key must not be sent an empty bearer.
        #expect(RemoteEstimatePayload.request(url: url, key: nil, body: body)
            .value(forHTTPHeaderField: "Authorization") == nil)
        #expect(RemoteEstimatePayload.request(url: url, key: "   ", body: body)
            .value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Photos

    @Test func thePhotoTravelsAsADataURLOnlyWhenPhotosAreAllowed() throws {
        let png = try #require(Fixtures.pngData(width: 40, height: 30))
        let allowed = try RemoteEstimatePayload.content(
            for: .photo(png, description: "half of it left"), sendsPhotos: true
        )
        let body = try RemoteEstimatePayload.body(model: "m", mode: .strict, content: allowed)
        let messages = try sentMessages(in: body)
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
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
        let refused = try RemoteEstimatePayload.content(
            for: .photo(png, description: "half of it left"), sendsPhotos: false
        )
        let body = try RemoteEstimatePayload.body(model: "m", mode: .strict, content: refused)
        let messages = try sentMessages(in: body)
        let user = try #require(messages.last?["content"] as? String)
        #expect(user.contains("half of it left"))
        #expect(!user.contains("data:image"))
        // Nothing is attached, so nothing may invite the model to describe a photograph.
        #expect(!user.contains("attached photo"))
    }

    @Test func aPhotoWithNoWordsIsRefusedWhenPhotosMayNotBeSent() throws {
        let png = try #require(Fixtures.pngData(width: 20, height: 20))
        #expect(throws: EstimationError.self) {
            try RemoteEstimatePayload.content(for: .photo(png, description: "   "), sendsPhotos: false)
        }
        #expect(throws: EstimationError.self) {
            try RemoteEstimatePayload.content(for: .photo(png, description: nil), sendsPhotos: false)
        }
    }

    @Test func bytesThatAreNotAnImageAreRefusedBeforeAnythingIsSent() {
        #expect(throws: EstimationError.self) {
            try RemoteEstimatePayload.content(for: .photo(Data("nope".utf8), description: nil), sendsPhotos: true)
        }
    }

    @Test func aLargePhotoIsDownscaledBeforeItIsEncoded() throws {
        let png = try #require(Fixtures.pngData(width: 2400, height: 1800))
        let dataURL = try #require(RemoteEstimatePayload.imageDataURL(for: png))
        let encoded = try #require(dataURL.split(separator: ",", maxSplits: 1).last.map(String.init))
        let jpeg = try #require(Data(base64Encoded: encoded))
        let decoded = try #require(PhotoData.downscaled(jpeg, maxPixelSize: 4096))
        #expect(decoded.width == RemoteEstimatePayload.imagePixelSize)
        #expect(decoded.height == RemoteEstimatePayload.imagePixelSize * 3 / 4)
    }

    // MARK: - Answers

    @Test func theEnvelopeIsReadDownToTheFirstChoicesText() throws {
        let body = Data(#"{"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":"{\"items\":[],\"note\":\"none\"}"},"finish_reason":"stop"}],"usage":{"total_tokens":12}}"#.utf8)
        let answer = try JSONDecoder().decode(RemoteCompletionResponse.self, from: body)
        #expect(answer.finishReason == "stop")
        #expect(answer.refusal == nil)
        let reply = try #require(answer.content)
        let estimate = try RemoteEstimatePayload.estimate(from: reply)
        #expect(estimate.items.isEmpty)
        #expect(estimate.note == "none")
    }

    @Test func anEnvelopeWithoutChoicesCarriesNoText() throws {
        let answer = try JSONDecoder().decode(
            RemoteCompletionResponse.self, from: Data(#"{"choices":[]}"#.utf8)
        )
        #expect(answer.content == nil)
        #expect(answer.finishReason == nil)
    }

    @Test func aRefusalIsCarriedInItsOwnField() throws {
        let body = Data(#"{"choices":[{"message":{"content":null,"refusal":"I can't help with that."},"finish_reason":"stop"}]}"#.utf8)
        let answer = try JSONDecoder().decode(RemoteCompletionResponse.self, from: body)
        #expect(answer.content == nil)
        #expect(answer.refusal == "I can't help with that.")
    }

    @Test func theHappyAnswerBecomesAnEstimate() throws {
        let estimate = try RemoteEstimatePayload.estimate(from: happyReply)
        #expect(estimate.items.count == 2)
        #expect(estimate.items[0].name == "Scrambled eggs")
        #expect(estimate.items[0].lookupTerm == "scrambled eggs")
        #expect(estimate.items[0].grams == 120)
        #expect(estimate.items[1].grams == 45)
        #expect(estimate.meal == .breakfast)
        #expect(estimate.note == "Assumed two eggs.")
    }

    @Test func markdownFencedJSONIsStillRead() throws {
        let reply = """
            Here is the estimate:
            ```json
            {"items": [{"name": "Apple", "lookupTerm": "apple raw", "grams": 180}], "meal": "snack", "note": "One medium apple."}
            ```
            Hope that helps.
            """
        let estimate = try RemoteEstimatePayload.estimate(from: reply)
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Apple")
        #expect(estimate.items[0].grams == 180)
        #expect(estimate.note == "One medium apple.")
    }

    @Test func aWeightWrittenAsTextIsStillAWeight() throws {
        let reply = #"{"items":[{"name":"Rice","lookup_term":"white rice cooked","grams":"about 220 g"},{"name":"Soy sauce","lookupTerm":"soy sauce","grams":"a splash"}],"note":"Guessed the rice."}"#
        let estimate = try RemoteEstimatePayload.estimate(from: reply)
        #expect(estimate.items.count == 2)
        #expect(estimate.items[0].grams == 220)
        #expect(estimate.items[0].lookupTerm == "white rice cooked")
        // No number anywhere in it reads as no weight, which `EstimateConversion` drops:
        // a dropped row is honest where an invented weight is not.
        #expect(estimate.items[1].grams == 0)
    }

    @Test func aMissingOrUnknownMealIsASnack() throws {
        let missing = try RemoteEstimatePayload.estimate(from: #"{"items":[],"note":""}"#)
        #expect(missing.meal == .snack)
        let unknown = try RemoteEstimatePayload.estimate(from: #"{"items":[],"meal":"brunch"}"#)
        #expect(unknown.meal == .snack)
        // Trimmed and lowercased first, because a model writes the word as a word.
        let spelled = try RemoteEstimatePayload.estimate(from: #"{"items":[],"meal":" Dinner "}"#)
        #expect(spelled.meal == .dinner)
    }

    @Test func anEmptyEstimateIsAnEstimateAndNotAFailure() throws {
        let estimate = try RemoteEstimatePayload.estimate(
            from: #"{"items":[],"meal":"lunch","note":"Nothing recognisable in the photo."}"#
        )
        #expect(estimate.items.isEmpty)
        #expect(estimate.meal == .lunch)
        #expect(estimate.note == "Nothing recognisable in the photo.")
    }

    @Test func oneUnreadableItemCostsThatItemAndNotTheMeal() throws {
        let estimate = try RemoteEstimatePayload.estimate(
            from: #"{"items":["a cup of tea",{"name":"Tea","lookupTerm":"tea brewed","grams":200}]}"#
        )
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Tea")
        #expect(estimate.note.isEmpty)
    }

    @Test func anAnswerWithNoReadableObjectInItFails() {
        for reply in ["I'm sorry, I can't help with that.", "", #"{"items": ["#, #"{"items": [}"#] {
            #expect(throws: EstimationError.self) {
                try RemoteEstimatePayload.estimate(from: reply)
            }
        }
    }

    // MARK: - Rejections

    @Test func aRejectionAboutTheSchemaOrTheTemperatureAsksForAPlainRetry() {
        let fastAPI = Data(#"{"detail":[{"loc":["body","response_format","type"],"msg":"unexpected value"}]}"#.utf8)
        #expect(RemoteEstimatePayload.rejectsStrictRequest(status: 422, body: fastAPI))
        let noSchema = Data(#"{"error":{"message":"json_schema is not supported","code":400}}"#.utf8)
        #expect(RemoteEstimatePayload.rejectsStrictRequest(status: 400, body: noSchema))
        let noTemperature = Data(#"{"error":{"message":"Unsupported value: 'temperature' does not support 0."}}"#.utf8)
        #expect(RemoteEstimatePayload.rejectsStrictRequest(status: 400, body: noTemperature))
        // Auth and rate limits say nothing about the shape of the request.
        #expect(!RemoteEstimatePayload.rejectsStrictRequest(status: 401, body: noSchema))
        #expect(!RemoteEstimatePayload.rejectsStrictRequest(status: 429, body: noSchema))
        #expect(!RemoteEstimatePayload.rejectsStrictRequest(status: 200, body: noSchema))
        let otherFailure = Data(#"{"error":{"message":"model not found"}}"#.utf8)
        #expect(!RemoteEstimatePayload.rejectsStrictRequest(status: 400, body: otherFailure))
    }

    @Test func eachRejectionBecomesSomethingTheSheetCanSay() {
        #expect(RemoteEstimatePayload.error(status: 401, body: Data()) == .unavailable(
            "The endpoint refused the API key. Check it in Settings."
        ))
        #expect(RemoteEstimatePayload.error(status: 413, body: Data()) == .tooLong)
        let tooLong = Data(#"{"error":{"message":"This model's maximum context length is 4096 tokens"}}"#.utf8)
        #expect(RemoteEstimatePayload.error(status: 400, body: tooLong) == .tooLong)
        let filtered = Data(#"{"error":{"message":"The response was blocked by a content_filter"}}"#.utf8)
        #expect(RemoteEstimatePayload.error(status: 400, body: filtered) == .guardrail)
    }

    @Test func aServersOwnWordsAreShownWithTheStatus() {
        let mapped = RemoteEstimatePayload.error(status: 503, body: Data(#"{"error":"upstream is down"}"#.utf8))
        guard case .failed(let message) = mapped else {
            Issue.record("expected failed, got \(mapped)")
            return
        }
        #expect(message.contains("503"))
        #expect(message.contains("upstream is down"))
        guard case .failed(let bare) = RemoteEstimatePayload.error(status: 500, body: Data()) else {
            Issue.record("expected failed for an empty body")
            return
        }
        #expect(bare.contains("500"))
    }
}
