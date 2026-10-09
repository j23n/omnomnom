import Foundation
import os

/// Runs the loop: ask, run the searches it asks for, send the results back, until it
/// answers or the round limit is reached.
///
/// **Main-actor rather than an actor**, unlike every other estimator here, and for a
/// reason that is not laziness: the searches end at the shared `ModelContext` — the
/// product one writes a cache row — so the loop has to be where that context is. What that
/// costs is decoding a few kilobytes on the main thread per round trip, which is the same
/// bargain `BarcodeLookupFlow` already makes. What it buys is that the tools are ordinary
/// calls rather than hops across an isolation boundary with a protocol to carry them.
///
/// Configuration is injected rather than read here, for the same reasons the other remote
/// estimator gives: the endpoint lives in `UserDefaults`, the key in the keychain, and a
/// type that reached for both could not be tested.
@MainActor
final class AnthropicLineResolver: LineDriving {
    private let settings: AnthropicSettings
    private let key: String?
    private let transport: any HTTPTransport
    private let searcher: any LineSearching

    /// `settings` is resolved here rather than at each use, which is the fix for a bug
    /// worth remembering. Both its fields default — the address and the model — and
    /// `resolved` existed to say so; but `messagesURL` called it internally while the model
    /// was read raw, so an empty Model field went out as `"model": ""` and the API answered
    /// *400: model string should have at least 1 character*. The Settings footer promising
    /// the default was telling the truth about the intent and not about the code. Filling
    /// the defaults in once, at the boundary, is what makes that class of mistake
    /// impossible rather than fixed.
    init(
        settings: AnthropicSettings,
        key: String?,
        searcher: any LineSearching,
        transport: any HTTPTransport = URLSessionTransport(timeout: AnthropicPayload.timeout)
    ) {
        self.settings = settings.resolved
        self.key = key
        self.searcher = searcher
        self.transport = transport
    }

    func resolve(_ input: EstimationInput) async throws -> DrivenLine {
        guard settings.isUsable, let url = settings.messagesURL else {
            throw EstimationError.unavailable("Add your Anthropic key and the model to use in Settings first.")
        }
        var pool = LineCandidatePool()
        var messages = [
            AnthropicMessage.user(
                try AnthropicPayload.opening(for: input, sendsPhotos: settings.sendsPhotos)
            )
        ]
        for round in 1...LinePrompt.maximumRounds {
            let data = try await send(messages, to: url, round: round)
            switch try AnthropicPayload.step(from: data) {
            case .answer(let answer):
                AppLog.estimation.info(
                    "resolved a line in \(round) round(s): \(answer.items.count) items from \(pool.count) candidates"
                )
                return DrivenLine(answer: answer, pool: pool)
            case .searches(let turn, let calls):
                messages.append(.assistant(turn))
                messages.append(.user(await results(for: calls, pool: &pool)))
            }
        }
        // The last round's results were sent and will not be read, which is a wasted
        // request rather than a lost one: it was already in flight when the limit was
        // reached. Not retried under a different prompt either — a model that searched
        // five times without answering is not going to answer the sixth time for free.
        AppLog.estimation.info("gave up after \(LinePrompt.maximumRounds) rounds")
        throw EstimationError.failed(LinePrompt.keptSearching)
    }

    /// One round trip, with every failure already in the user's terms.
    private func send(_ messages: [AnthropicMessage], to url: URL, round: Int) async throws -> Data {
        let body = try AnthropicPayload.body(
            model: settings.model, messages: messages, searchesProducts: searcher.searchesProducts
        )
        let request = AnthropicPayload.request(url: url, key: key, body: body)
        let host = Self.host(of: url)
        let started = Date()
        let (data, response) = try await transport.fetch(request, host: host)
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.estimation.info(
            "\(host, privacy: .public) answered \(response.statusCode) in \(milliseconds) ms, round \(round)"
        )
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw AnthropicPayload.error(status: response.statusCode, body: data)
        }
        guard data.count <= AnthropicPayload.maximumBodySize else {
            AppLog.estimation.error("\(host, privacy: .public) answered \(data.count) bytes, too many for a reply")
            throw EstimationError.failed("the answer was too large to read.")
        }
        return data
    }

    /// Runs what the model asked for and keeps the rows, in the order it asked.
    ///
    /// **One search at a time**, which is the one place this path leaves latency on the
    /// table: a line naming five foods that all need a product search is five requests
    /// abroad in series. Kept serial on purpose for now — the searches mutate one pool and
    /// numbering them in a fixed order is what makes the same line resolve the same way
    /// twice, and the round trip this path already removed is the larger one, since a
    /// product is now fetched by barcode once for the row that won rather than once per
    /// term named. Running them concurrently is a measurable change on its own.
    ///
    /// Every call is answered, including one naming a tool this app does not have. A
    /// `tool_use` block left without a `tool_result` makes the next request invalid, so an
    /// unknown name gets an error result rather than silence.
    private func results(
        for calls: [AnthropicPayload.ToolCall], pool: inout LineCandidatePool
    ) async -> [JSONValue] {
        var blocks: [JSONValue] = []
        for call in calls {
            switch call.tool {
            case LinePrompt.foodTool:
                let found = pool.add(foods: await searcher.foods(matching: call.term))
                blocks.append(
                    AnthropicPayload.toolResult(id: call.id, text: LinePrompt.results(found))
                )
            case LinePrompt.productTool where searcher.searchesProducts:
                let found = pool.add(products: await searcher.products(matching: call.term))
                blocks.append(
                    AnthropicPayload.toolResult(id: call.id, text: LinePrompt.results(found))
                )
            default:
                AppLog.estimation.info("asked for a tool this app does not have")
                blocks.append(
                    AnthropicPayload.toolResult(
                        id: call.id,
                        text: LinePrompt.noSuchSearch,
                        isError: true
                    )
                )
            }
        }
        return blocks
    }

    /// What the log and the sentences call this path's endpoint.
    private nonisolated static func host(of url: URL) -> String {
        TransportFailure.host(of: url, fallback: "the API")
    }
}
