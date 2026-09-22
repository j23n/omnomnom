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
