import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// A transport that answers a script in order and keeps every request it was given, so a
/// test can assert what the second round trip carried as well as what came back.
///
/// `FakeTransport` answers one reply and is right for a client that makes one request; a
/// loop makes several and the point of testing it is what happens between them.
actor ScriptedTransport: HTTPTransport {
    private var replies: [String]
    private(set) var bodies: [Data] = []

    init(_ replies: [String]) {
        self.replies = replies
    }

    var rounds: Int { bodies.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        bodies.append(request.httpBody ?? Data())
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { throw URLError(.badServerResponse) }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        return (Data(replies.removeFirst().utf8), response)
    }
}

/// Searches that answer from a script and record what they were asked, standing in for the
/// device's own tables and for Open Food Facts.
@MainActor
final class FakeLineSearch: LineSearching {
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

/// The loop: ask, run the searches it asks for, send the results back, until it answers.
@MainActor
struct AnthropicLineResolverTests {
    /// One request's body, as JSON. Parsed here rather than inside the transport, because
    /// a dictionary of `Any` is not sendable and has no business crossing out of an actor.
    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func settings() -> AnthropicSettings {
        AnthropicSettings(baseURL: "https://api.anthropic.com/v1", model: "claude-opus-5-5")
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

    /// A reply that asks for one food search.
    private func searchReply(id: String = "toolu_1", term: String) -> String {
        """
        {"stop_reason":"tool_use","content":[
          {"type":"tool_use","id":"\(id)","name":"search_foods","input":{"term":"\(term)"}}
        ]}
        """
    }

    /// A reply that answers with one item.
    private func answerReply(
        candidate: Int, grams: Double = 45, certainty: String = "certain", meal: String = "breakfast"
    ) -> String {
        let item = """
            {\\"name\\":\\"oats\\",\\"candidate\\":\(candidate),\\"grams\\":\(grams),\\"certainty\\":\\"\(certainty)\\",\\"implausible\\":false}
            """
        return """
            {"stop_reason":"end_turn","content":[{"type":"text","text":"{\\"items\\":[\(item)],\\"meal\\":\\"\(meal)\\",\\"note\\":\\"\\"}"}]}
            """
    }

    private func resolver(
        _ replies: [String], searcher: FakeLineSearch
    ) -> (AnthropicLineResolver, ScriptedTransport) {
        let transport = ScriptedTransport(replies)
        return (
            AnthropicLineResolver(
                settings: settings(), key: "sk-test", searcher: searcher, transport: transport
            ),
            transport
        )
    }

    @Test func aSearchIsRunHereAndItsRowsGoBack() async throws {
        let searcher = FakeLineSearch()
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

        // The second request replays the first turn and answers the call by its id. A
        // tool_use left without a tool_result makes the request invalid.
        let second = try json(await transport.bodies[1])
        let messages = try #require(second["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        #expect(messages[1]["role"] as? String == "assistant")
        #expect(messages[2]["role"] as? String == "user")
        let results = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(results.first?["type"] as? String == "tool_result")
        #expect(results.first?["tool_use_id"] as? String == "toolu_1")
        let content = try #require(results.first?["content"] as? [[String: Any]])
        #expect((content.first?["text"] as? String)?.contains("id 1: Oat flakes") == true)
    }

    @Test func theModelsOwnTurnGoesBackUntouched() async throws {
        // Including a reasoning block it cannot read: those are bound to the conversation
        // that produced them, so rebuilding the turn out of the parts this app understands
        // would be an edit to the history.
        let searcher = FakeLineSearch()
        let turn = """
            {"stop_reason":"tool_use","content":[
              {"type":"thinking","thinking":"","signature":"sig-xyz"},
              {"type":"tool_use","id":"toolu_1","name":"search_foods","input":{"term":"oats"}}
            ]}
            """
        let (subject, transport) = resolver([turn, answerReply(candidate: 0)], searcher: searcher)
        _ = try await subject.resolve(.text("oats"))

        let messages = try #require(json(await transport.bodies[1])["messages"] as? [[String: Any]])
        let assistant = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(assistant.count == 2)
        #expect(assistant.first?["type"] as? String == "thinking")
        #expect(assistant.first?["signature"] as? String == "sig-xyz")
    }

    @Test func idsAreOneSequenceOverBothSearches() async throws {
        // Two sources with no shared namespace, so the ids are this request's own. That is
        // what lets a product be named at all, and what makes the guard one comparison.
        let searcher = FakeLineSearch()
        searcher.foodHits["oats"] = [match(1, "Oat flakes"), match(2, "Biscuits, oat")]
        searcher.productHits["oatly"] = [product("7394376615955", "Oatly Oat Drink", brand: "Oatly")]
        let both = """
            {"stop_reason":"tool_use","content":[
              {"type":"tool_use","id":"t1","name":"search_foods","input":{"term":"oats"}},
              {"type":"tool_use","id":"t2","name":"search_products","input":{"term":"oatly"}}
            ]}
            """
        let (subject, _) = resolver([both, answerReply(candidate: 3)], searcher: searcher)
        let driven = try await subject.resolve(.text("oats and oatly"))

        #expect(driven.pool.count == 3)
        #expect(driven.pool.candidate(id: 1)?.name == "Oat flakes")
        #expect(driven.pool.candidate(id: 2)?.name == "Biscuits, oat")
        let third = try #require(driven.pool.candidate(id: 3))
        #expect(third.name == "Oatly Oat Drink")
        #expect(third.isProduct)
        #expect(third.pick == .product(code: "7394376615955"))
    }

    @Test func withTheOptInOffTheProductSearchIsNeitherOfferedNorRun() async throws {
        let searcher = FakeLineSearch()
        searcher.searchesProducts = false
        searcher.productHits["oatly"] = [product("1", "Oatly Oat Drink")]
        let asked = """
            {"stop_reason":"tool_use","content":[
              {"type":"tool_use","id":"t1","name":"search_products","input":{"term":"oatly"}}
            ]}
            """
        let (subject, transport) = resolver([asked, answerReply(candidate: 0)], searcher: searcher)
        _ = try await subject.resolve(.text("oatly"))

        // Not declared, so a model should not ask — and if it does anyway, nothing leaves
        // the device and the call is answered with an error rather than dropped.
        let first = try json(await transport.bodies[0])
        let tools = try #require(first["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(searcher.productTerms.isEmpty)
        let messages = try #require(json(await transport.bodies[1])["messages"] as? [[String: Any]])
        let results = try #require(messages[2]["content"] as? [[String: Any]])
        #expect(results.first?["is_error"] as? Bool == true)
    }

    @Test func aSearchThatFoundNothingSaysSoRatherThanAnsweringBlank() async throws {
        // "Nothing" is information worth acting on, and a blank result invites a model to
        // assume the call failed and spend a round trip repeating it.
        let searcher = FakeLineSearch()
        let (subject, transport) = resolver(
            [searchReply(term: "unobtainium"), answerReply(candidate: 0)], searcher: searcher
        )
        _ = try await subject.resolve(.text("unobtainium"))
        let messages = try #require(json(await transport.bodies[1])["messages"] as? [[String: Any]])
        let results = try #require(messages[2]["content"] as? [[String: Any]])
        let content = try #require(results.first?["content"] as? [[String: Any]])
        #expect((content.first?["text"] as? String)?.contains("No rows match") == true)
    }

    @Test func aModelThatKeepsSearchingIsStoppedAtTheRoundLimit() async throws {
        let searcher = FakeLineSearch()
        let forever = Array(repeating: searchReply(term: "oats"), count: AnthropicPayload.maximumRounds)
        let (subject, transport) = resolver(forever, searcher: searcher)
        await #expect(throws: EstimationError.failed(AnthropicPayload.keptSearching)) {
            try await subject.resolve(.text("oats"))
        }
        // Bounded: a model that will not answer costs a fixed number of requests.
        let rounds = await transport.rounds
        #expect(rounds == AnthropicPayload.maximumRounds)
    }

    @Test func anUnconfiguredProviderSaysWhatIsMissingRatherThanFailing() async throws {
        let searcher = FakeLineSearch()
        let subject = AnthropicLineResolver(
            settings: AnthropicSettings(baseURL: "not a url at all"), key: nil,
            searcher: searcher, transport: ScriptedTransport([])
        )
        await #expect(throws: EstimationError.self) {
            try await subject.resolve(.text("oats"))
        }
    }

    @Test func bothSettingsFieldsDefaultSoAKeyIsAllItTakes() throws {
        let empty = AnthropicSettings()
        #expect(empty.isUsable)
        #expect(empty.resolved.model == AnthropicPayload.defaultModel)
        #expect(empty.messagesURL?.absoluteString == "https://api.anthropic.com/v1/messages")
        // Tolerant about what people paste: a trailing slash, or the path already typed.
        #expect(AnthropicSettings(baseURL: "https://api.anthropic.com/v1/").messagesURL?.absoluteString
            == "https://api.anthropic.com/v1/messages")
        #expect(AnthropicSettings(baseURL: "https://api.anthropic.com/v1/messages").messagesURL?.absoluteString
            == "https://api.anthropic.com/v1/messages")
        #expect(AnthropicSettings(baseURL: "ftp://example.invalid").messagesURL == nil)
    }
}
