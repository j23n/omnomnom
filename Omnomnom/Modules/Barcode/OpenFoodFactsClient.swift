import Foundation
import os

/// One HTTP GET, so the client can be tested without a network.
nonisolated protocol HTTPTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport: an ephemeral session that caches and persists nothing, fails at
/// once without connectivity instead of waiting for it, and gives up after `timeout`.
nonisolated struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(timeout: TimeInterval = 10) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Why a lookup failed. A product Open Food Facts does not know is `nil`, not an error.
nonisolated enum OpenFoodFactsError: Error, Sendable {
    /// The code is not all digits, so no request was made.
    case invalidBarcode
    /// The search text was blank or could not be put in a URL, so no request was made.
    case invalidQuery
    /// A non-2xx status other than 404.
    case http(Int)
    /// The body was not the JSON envelope expected, or too large to be one.
    case decoding
    /// The transport failed: offline, timed out, or the host did not answer.
    case network(any Error)
}

/// Looks products up on Open Food Facts. An actor so decoding runs off the main
/// actor; one instance per lookup is fine, since the transport holds the session.
actor OpenFoodFactsClient {
    nonisolated static let fields = "code,product_name,brands,nutriments,quantity,product_quantity_unit"
    nonisolated static let endpoint = "https://world.openfoodfacts.org/api/v2/product/"
    /// Full-text search lives on its own host; the product endpoint has never done it.
    nonisolated static let searchEndpoint = "https://search.openfoodfacts.org/search"
    /// Asked for, not shown: most of a broad query's hits hold no values at all, so
    /// the page is wide enough that filtering it still leaves a screenful.
    nonisolated static let searchPageSize = 50
    /// Shown. More than this is a scroll through other people's guesses at a name.
    nonisolated static let maximumResults = 20
    /// A product with only the requested fields is a few kilobytes; anything above this is not one.
    nonisolated static let maximumBodySize = 1 << 20
    /// A page of products is larger than one, but not by much.
    nonisolated static let maximumSearchBodySize = 4 << 20

    private let transport: any HTTPTransport
    private let userAgent: String

    init(transport: any HTTPTransport, userAgent: String) {
        self.transport = transport
        self.userAgent = userAgent
    }

    /// The product behind `barcode`, or `nil` when Open Food Facts has no record of it
    /// (a 404, or a 200 whose `status` is not 1).
    func product(for barcode: String) async throws -> ProductRecord? {
        let request = try Self.request(for: barcode, userAgent: userAgent)
        let (data, response) = try await fetch(request)
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            AppLog.barcode.error("lookup answered \(response.statusCode)")
            throw OpenFoodFactsError.http(response.statusCode)
        }
        guard data.count <= Self.maximumBodySize else {
            AppLog.barcode.error("lookup body too large: \(data.count) bytes")
            throw OpenFoodFactsError.decoding
        }
        let envelope: ProductResponse
        do {
            envelope = try JSONDecoder().decode(ProductResponse.self, from: data)
        } catch {
            AppLog.barcode.error("lookup body not decodable: \(error.localizedDescription, privacy: .private)")
            throw OpenFoodFactsError.decoding
        }
        guard envelope.isFound, let record = envelope.product else { return nil }
        return record
    }

    /// Products whose name or brand matches `text`, most relevant first, at most
    /// `maximumResults` of them.
    ///
    /// A hit is a starting point, not a record: it carries whatever the search index
    /// holds, and a great many entries hold a name and nothing else. Those are dropped
    /// here rather than offered, since choosing one leads nowhere. The caller resolves
    /// the one the user picks through `product(for:)`, which is the endpoint that
    /// answers for a product properly.
    func products(matching text: String) async throws -> [ProductRecord] {
        let request = try Self.searchRequest(for: text, userAgent: userAgent)
        let (data, response) = try await fetch(request)
        guard (200..<300).contains(response.statusCode) else {
            AppLog.barcode.error("product search answered \(response.statusCode)")
            throw OpenFoodFactsError.http(response.statusCode)
        }
        guard data.count <= Self.maximumSearchBodySize else {
            AppLog.barcode.error("product search body too large: \(data.count) bytes")
            throw OpenFoodFactsError.decoding
        }
        do {
            let envelope = try JSONDecoder().decode(ProductSearchResponse.self, from: data)
            if envelope.skipped > 0 {
                AppLog.barcode.error("product search: \(envelope.skipped) hits in a shape this app does not read")
            }
            if envelope.incomplete > 0 {
                AppLog.barcode.debug("product search: \(envelope.incomplete) hits dropped for missing macronutrients")
            }
            return Array(envelope.products.prefix(Self.maximumResults))
        } catch {
            // The body is the only thing that says why, and a search answer is public
            // data, so a prefix of it goes in the log where the next run can use it.
            AppLog.barcode.error(
                "search body not decodable: \(error.localizedDescription, privacy: .private); began: \(Self.preview(of: data), privacy: .private)"
            )
            throw OpenFoodFactsError.decoding
        }
    }

    /// The first characters of a body, whitespace collapsed, for a log line that has to
    /// explain a decoding failure without carrying the whole response.
    nonisolated static func preview(of data: Data, limit: Int = 400) -> String {
        let text = String(decoding: data.prefix(limit * 4), as: UTF8.self)
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    /// The GET for a search: the same fields as a product lookup, one page of them.
    /// The text is the user's, so it is percent-encoded as a query item rather than
    /// pasted into the URL.
    nonisolated static func searchRequest(for text: String, userAgent: String) throws -> URLRequest {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, var components = URLComponents(string: searchEndpoint) else {
            throw OpenFoodFactsError.invalidQuery
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "page_size", value: String(searchPageSize)),
        ]
        guard let url = components.url else { throw OpenFoodFactsError.invalidQuery }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The GET for one barcode: the v2 product endpoint restricted to the fields read,
    /// with the descriptive User-Agent Open Food Facts asks for.
    nonisolated static func request(for barcode: String, userAgent: String) throws -> URLRequest {
        let isDigits = !barcode.isEmpty && barcode.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
        guard isDigits, let url = URL(string: "\(endpoint)\(barcode).json?fields=\(fields)") else {
            throw OpenFoodFactsError.invalidBarcode
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.get(request)
        } catch {
            AppLog.barcode.error("lookup failed: \(error.localizedDescription, privacy: .private)")
            throw OpenFoodFactsError.network(error)
        }
    }
}
