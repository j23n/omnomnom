import Foundation
import Testing
@testable import Omnomnom

/// What the fake transport answers with, fixed at construction.
nonisolated enum FakeReply: Sendable {
    case response(status: Int, body: String)
    case failure(any Error)
}

/// Records every request and answers each with the same reply.
actor FakeTransport: HTTPTransport {
    private let reply: FakeReply
    private(set) var requests: [URLRequest] = []

    init(reply: FakeReply) {
        self.reply = reply
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch reply {
        case .failure(let error):
            throw error
        case .response(let status, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { throw URLError(.badServerResponse) }
            return (Data(body.utf8), response)
        }
    }
}

struct OpenFoodFactsClientTests {
    private let userAgent = "Omnomnom/0.1 (https://github.com/j23n/omnomnom)"
    private let code = "4006381333931"
    private let found = #"{"code":"4006381333931","status":1,"product":{"code":"4006381333931","product_name":"Nutella","brands":"Ferrero","nutriments":{"energy-kcal_100g":539}}}"#
    private let missing = #"{"code":"4006381333931","status":0,"status_verbose":"product not found"}"#

    private func makeClient(_ reply: FakeReply) -> (OpenFoodFactsClient, FakeTransport) {
        let transport = FakeTransport(reply: reply)
        return (OpenFoodFactsClient(transport: transport, userAgent: userAgent), transport)
    }

    @Test func requestTargetsTheV2EndpointWithFieldsAndUserAgent() async throws {
        let (client, transport) = makeClient(.response(status: 200, body: found))
        _ = try await client.product(for: code)
        let requests = await transport.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.url?.absoluteString == "https://world.openfoodfacts.org/api/v2/product/4006381333931.json?fields=code,product_name,brands,nutriments,quantity,product_quantity_unit")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == userAgent)
        #expect(request.timeoutInterval == 10)
    }

    @Test func foundProductIsDecoded() async throws {
        let (client, _) = makeClient(.response(status: 200, body: found))
        let fetched = try await client.product(for: code)
        let record = try #require(fetched)
        #expect(record.name == "Nutella")
        #expect(record.brand == "Ferrero")
        #expect(record.per100g.energy == 539)
    }

    @Test func statusZeroIsNil() async throws {
        let (client, _) = makeClient(.response(status: 200, body: missing))
        let record = try await client.product(for: code)
        #expect(record == nil)
    }

    @Test func notFoundIsNil() async throws {
        let (client, _) = makeClient(.response(status: 404, body: missing))
        let record = try await client.product(for: code)
        #expect(record == nil)
    }

    @Test func serverErrorThrowsHTTP() async {
        let (client, _) = makeClient(.response(status: 500, body: "boom"))
        do {
            _ = try await client.product(for: code)
            Issue.record("expected an error")
        } catch OpenFoodFactsError.http(let status) {
            #expect(status == 500)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func malformedBodyThrowsDecoding() async {
        let (client, _) = makeClient(.response(status: 200, body: "<html>"))
        do {
            _ = try await client.product(for: code)
            Issue.record("expected an error")
        } catch OpenFoodFactsError.decoding {
            // The expected outcome.
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func oversizedBodyThrowsDecoding() async {
        let padding = String(repeating: " ", count: OpenFoodFactsClient.maximumBodySize + 1)
        let (client, _) = makeClient(.response(status: 200, body: found + padding))
        do {
            _ = try await client.product(for: code)
            Issue.record("expected an error")
        } catch OpenFoodFactsError.decoding {
            // The expected outcome: the body is never decoded.
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func transportFailureThrowsNetworkWithTheCause() async {
        let (client, _) = makeClient(.failure(URLError(.notConnectedToInternet)))
        do {
            _ = try await client.product(for: code)
            Issue.record("expected an error")
        } catch OpenFoodFactsError.network(let cause) {
            #expect((cause as? URLError)?.code == .notConnectedToInternet)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func nonDigitCodeNeverReachesTheTransport() async {
        let (client, transport) = makeClient(.response(status: 200, body: found))
        do {
            _ = try await client.product(for: "12ab")
            Issue.record("expected an error")
        } catch OpenFoodFactsError.invalidBarcode {
            let requests = await transport.requests
            #expect(requests.isEmpty)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

/// Searching Open Food Facts by name, which is a different host and a different envelope.
struct OpenFoodFactsSearchTests {
    private let userAgent = "Omnomnom/0.1 (https://github.com/j23n/omnomnom)"
    /// Complete macronutrients, which a hit needs before it is offered at all.
    private let macros = #""nutriments":{"energy-kcal_100g":571,"proteins_100g":8.6,"carbohydrates_100g":49.5,"fat_100g":37.3}"#
    private let hits = #"""
    {"count":2,"page":1,"hits":[
      {"code":"8000500037560","product_name":"Kinder Bueno","brands":"Ferrero",
       "nutriments":{"energy-kcal_100g":571,"proteins_100g":8.6,"carbohydrates_100g":49.5,"fat_100g":37.3}},
      {"code":"5449000000996","product_name":"Coca-Cola","brands":"Coca-Cola","quantity":"33 cl",
       "nutriments":{"energy-kcal_100g":42,"proteins_100g":0,"carbohydrates_100g":10.6,"fat_100g":0}}
    ]}
    """#
    private let legacy = #"""
    {"count":1,"products":[{"code":"8000500037560","product_name":"Kinder Bueno","brands":"Ferrero",
      "nutriments":{"energy-kcal_100g":571,"proteins_100g":8.6,"carbohydrates_100g":49.5,"fat_100g":37.3}}]}
    """#

    private func makeClient(_ reply: FakeReply) -> (OpenFoodFactsClient, FakeTransport) {
        let transport = FakeTransport(reply: reply)
        return (OpenFoodFactsClient(transport: transport, userAgent: userAgent), transport)
    }

    @Test func requestCarriesTheQueryFieldsAndUserAgent() throws {
        let request = try OpenFoodFactsClient.searchRequest(for: "kinder bueno", userAgent: userAgent)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host() == "search.openfoodfacts.org")
        #expect(url.path() == "/search")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["q"] == "kinder bueno")
        #expect(items["fields"] == OpenFoodFactsClient.fields)
        #expect(items["page_size"] == String(OpenFoodFactsClient.searchPageSize))
        #expect(request.value(forHTTPHeaderField: "User-Agent") == userAgent)
    }

    @Test func aQueryWithSpacesAndAmpersandsIsEncodedNotPasted() throws {
        let request = try OpenFoodFactsClient.searchRequest(for: "m&m's peanut", userAgent: userAgent)
        let url = try #require(request.url)
        #expect(url.absoluteString.contains("q=m%26m's%20peanut") || url.absoluteString.contains("q=m%26m%27s%20peanut"))
    }

    @Test func blankQueriesNeverLeaveTheDevice() {
        #expect(throws: OpenFoodFactsError.self) {
            _ = try OpenFoodFactsClient.searchRequest(for: "   ", userAgent: userAgent)
        }
    }

    @Test func hitsAreRead() async throws {
        let (client, transport) = makeClient(.response(status: 200, body: hits))
        let found = try await client.products(matching: "kinder")
        #expect(found.map(\.code) == ["8000500037560", "5449000000996"])
        #expect(found[0].name == "Kinder Bueno")
        #expect(found[0].brand == "Ferrero")
        #expect(found[0].per100g.energy == 571)
        #expect(found[1].measure == .volume)
        let requests = await transport.requests
        #expect(requests.count == 1)
    }

    @Test func theOlderEnvelopeIsReadToo() async throws {
        let (client, _) = makeClient(.response(status: 200, body: legacy))
        #expect(try await client.products(matching: "kinder").map(\.name) == ["Kinder Bueno"])
    }

    @Test func aHitWithoutACodeOrANameIsDropped() async throws {
        let body = #"""
        {"hits":[{"product_name":"No code",\#(macros)},{"code":"123",\#(macros)},
                 {"code":"456","product_name":"Kept",\#(macros)}]}
        """#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "x").map(\.code) == ["456"])
    }

    @Test func noMatchesIsAnEmptyListAndNotAnError() async throws {
        let (client, _) = makeClient(.response(status: 200, body: #"{"count":0,"hits":[]}"#))
        #expect(try await client.products(matching: "zzzz").isEmpty)
    }

    @Test func aServerErrorIsAnError() async {
        let (client, _) = makeClient(.response(status: 503, body: ""))
        await #expect(throws: OpenFoodFactsError.self) {
            _ = try await client.products(matching: "kinder")
        }
    }

    /// Trimmed from what search.openfoodfacts.org actually answered for "kinder bueno":
    /// brands is a list, sodium is in grams, and the envelope carries a pile of keys
    /// this app has no use for.
    private let live = #"""
    {"hits":[
      {"code":"80960270","brands":["Kinder Bueno","Kinder"],
       "nutriments":{"carbohydrates_100g":44.3,"energy-kcal_100g":592,"energy-kj_100g":2462,
         "fat_100g":41.6,"proteins_100g":9,"salt_100g":0.343,"saturated-fat_100g":22.89999961853,
         "sodium_100g":0.1372,"sugars_100g":35.2},
       "product_name":"Kinder Bueno Coconut"},
      {"code":"04749442","brands":["kinder"],"product_name":"kinder bueno"}],
     "aggregations":null,"facets":{},"charts":{},"page":1,"page_size":2,"page_count":752,
     "debug":{"query":{"size":2,"from":0}},"took":5,"timed_out":false,
     "count":1504,"is_count_exact":true,"warnings":null}
    """#

    @Test func theLiveResponseIsRead() async throws {
        let (client, _) = makeClient(.response(status: 200, body: live))
        let found = try await client.products(matching: "kinder bueno")
        // The second hit of the live answer holds a name, a brand and nothing else.
        #expect(found.map(\.code) == ["80960270"])
        let bueno = try #require(found.first)
        #expect(bueno.name == "Kinder Bueno Coconut")
        // brands is a list; the first of them is the one worth showing.
        #expect(bueno.brand == "Kinder Bueno")
        #expect(bueno.per100g.energy == 592)
        #expect(bueno.per100g.carbohydrates == 44.3)
        #expect(bueno.per100g.sugar == 35.2)
        // Open Food Facts reports sodium in grams; the app keeps milligrams.
        #expect(bueno.per100g.sodium == 137.2)
        // Absent from this product, and never invented.
        #expect(bueno.per100g.fiber == nil)
        #expect(bueno.isUsable)
    }

    @Test func aHitWithoutNutrimentsIsNotOffered() async throws {
        let (client, _) = makeClient(.response(status: 200, body: live))
        // The second hit of the live answer is a name, a brand and nothing else.
        #expect(try await client.products(matching: "kinder bueno").map(\.code) == ["80960270"])
    }

    @Test func aHitMissingOneMacronutrientIsNotOffered() async throws {
        let body = #"""
        {"hits":[
          {"code":"1","product_name":"No fat figure",
           "nutriments":{"energy-kcal_100g":571,"proteins_100g":8.6,"carbohydrates_100g":49.5}},
          {"code":"2","product_name":"Complete",\#(macros)}]}
        """#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "x").map(\.code) == ["2"])
    }

    @Test func aMacronutrientOfZeroCounts() async throws {
        let body = #"""
        {"hits":[{"code":"1","product_name":"Cola",
          "nutriments":{"energy-kcal_100g":42,"proteins_100g":0,"carbohydrates_100g":10.6,"fat_100g":0}}]}
        """#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "cola").map(\.code) == ["1"])
    }

    @Test func moreAreAskedForThanAreShown() async throws {
        #expect(OpenFoodFactsClient.searchPageSize > OpenFoodFactsClient.maximumResults)
        let listed = (1...OpenFoodFactsClient.searchPageSize).map { index in
            #"{"code":"\#(index)","product_name":"Product \#(index)",\#(macros)}"#
        }
        let body = #"{"hits":[\#(listed.joined(separator: ","))]}"#
        let (client, _) = makeClient(.response(status: 200, body: body))
        let found = try await client.products(matching: "product")
        #expect(found.count == OpenFoodFactsClient.maximumResults)
        #expect(found.first?.code == "1")
    }

    @Test func aNameHeldPerLanguageIsRead() async throws {
        let body = #"""
        {"hits":[{"code":"8000500037560",
          "product_name":{"main":"Kinder Bueno","en":"Kinder Bueno bar","fr":"Kinder Bueno"},
          "brands":"Ferrero","nutriments":{"energy-kcal_100g":571}}]}
        """#
        let (client, _) = makeClient(.response(status: 200, body: body))
        let found = try await client.products(matching: "kinder")
        #expect(found.map(\.name) == ["Kinder Bueno"])
    }

    @Test func aNameHeldPerLanguageWithoutAMainFallsBackToEnglish() async throws {
        let body = #"{"hits":[{"code":"1","product_name":{"fr":"Pomme","en":"Apple"},\#(macros)}]}"#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "apple").map(\.name) == ["Apple"])
    }

    @Test func aBarcodeSentAsANumberKeepsItsDigits() async throws {
        let body = #"{"hits":[{"code":8000500037560,"product_name":"Kinder Bueno",\#(macros)}]}"#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "kinder").map(\.code) == ["8000500037560"])
    }

    @Test func brandsSentAsAListAreRead() async throws {
        let body = #"{"hits":[{"code":"1","product_name":"Cola","brands":["Coca-Cola","Other"],\#(macros)}]}"#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "cola").map(\.brand) == ["Coca-Cola"])
    }

    @Test func oneUnreadableHitDoesNotLoseTheRest() async throws {
        let body = #"{"hits":["not a product",{"code":"1","product_name":"Kept",\#(macros)},42]}"#
        let (client, _) = makeClient(.response(status: 200, body: body))
        #expect(try await client.products(matching: "x").map(\.name) == ["Kept"])
    }

    @Test func aBodyPreviewIsShortAndOnOneLine() {
        let data = Data(#"{"hits":\#n  [ {"code":"1"} ]}"#.utf8)
        let preview = OpenFoodFactsClient.preview(of: data, limit: 20)
        #expect(preview.count <= 20)
        #expect(!preview.contains("\n"))
    }

    @Test func aBodyThatIsNotTheEnvelopeIsADecodingError() async {
        let (client, _) = makeClient(.response(status: 200, body: "<html>nope</html>"))
        await #expect(throws: OpenFoodFactsError.self) {
            _ = try await client.products(matching: "kinder")
        }
    }
}

/// The two opt-ins that allow a lookup at all.
struct BarcodeModuleGateTests {
    private func defaults(scanning: Bool, search: Bool) -> UserDefaults {
        let store = UserDefaults(suiteName: "com.j23n.omnomnom.tests.gate.\(scanning).\(search)") ?? .standard
        store.set(scanning, forKey: BarcodeModule.enabledKey)
        store.set(search, forKey: BarcodeModule.productSearchKey)
        return store
    }

    @Test func eitherWayInAllowsALookup() {
        #expect(BarcodeModule.lookupsAllowed(in: defaults(scanning: true, search: false)))
        #expect(BarcodeModule.lookupsAllowed(in: defaults(scanning: false, search: true)))
        #expect(BarcodeModule.lookupsAllowed(in: defaults(scanning: true, search: true)))
    }

    @Test func bothOffMeansNothingLeavesTheDevice() {
        #expect(BarcodeModule.lookupsAllowed(in: defaults(scanning: false, search: false)) == false)
    }
}
