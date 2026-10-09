import Foundation
import os

/// Runs the loop against an endpoint of the user's own: ask, run the searches it asks for,
/// send the results back, until it answers or the round limit is reached.
///
/// The counterpart of `AnthropicLineResolver`, driving the same searches from the same
/// instructions over the other protocol this app speaks, so a line reads the same whichever
/// of the two answered. It exists because the alternative for someone pointing the app at
/// their own server was the ladder — name a food, guess the wording a composition table
/// uses, search with the guess, then spend a second request checking what the retriever
/// did — and that is the thing being removed rather than kept for one provider.
///
/// **Main-actor rather than an actor**, for the reason the other driver gives: the searches
/// end at the shared `ModelContext` — the product one writes a cache row — so the loop has
/// to be where that context is. What that costs is decoding a few kilobytes on the main
/// thread per round trip; what it buys is that the tools are ordinary calls rather than hops
/// across an isolation boundary with a protocol to carry them.
///
/// **When the endpoint cannot call tools at all.** "OpenAI-compatible" is a family
/// resemblance rather than a specification, and tool calling is the part of the family a
/// small self-hosted server is likeliest not to have. There is no way to ask in advance and
/// no capability document to read, so the loop finds out by sending, and a rejection that
/// names tools or functions is turned into one sentence that says what the server cannot do
/// and what to do about it — see `OpenAICompatiblePayload.rejectsTools(status:body:)`. It is
/// `unavailable` rather than `failed` because it is a configuration to go and change, not a
/// request that went wrong. The other half of that failure, a server that accepts the
/// declaration and quietly ignores it, is left to the pool: a model that never searched can
/// only name ids this request never issued, and those read as "none of these", so the line
/// comes back as rows for the user to settle rather than as rows built on invented foods.
///
/// Configuration is injected rather than read here, for the reason both other remote
/// estimators give: the endpoint lives in `UserDefaults`, the key in the keychain, and a
/// type that reached for both could not be tested.
@MainActor
final class OpenAICompatibleLineResolver: LineDriving {
    private let settings: RemoteEstimatorSettings
    private let key: String?
    private let transport: any HTTPTransport
    private let searcher: any LineSearching

    /// `transport` is the same one-request seam the barcode client uses. Its method is
    /// named for a GET, but all it does is hand a finished `URLRequest` to a session, so a
    /// POST goes through it unchanged and a test can answer without a network.
    init(
        settings: RemoteEstimatorSettings,
        key: String?,
        searcher: any LineSearching,
        transport: any HTTPTransport = URLSessionTransport(timeout: OpenAICompatiblePayload.timeout)
    ) {
        self.settings = settings
        self.key = key
        self.searcher = searcher
        self.transport = transport
    }

    func resolve(_ input: EstimationInput) async throws -> DrivenLine {
        guard settings.isUsable, let url = settings.completionsURL else {
            throw EstimationError.unavailable("Set your endpoint's address and model in Settings first.")
        }
        var pool = LineCandidatePool()
        let content = try OpenAICompatiblePayload.content(for: input, sendsPhotos: settings.sendsPhotos)
        // The instructions are a message here rather than a field of the request, which is
        // the one difference in the shape of the conversation between the two drivers.
        var messages = [OpenAICompatiblePayload.systemMessage, OpenAICompatiblePayload.userMessage(content)]
        for round in 1...LinePrompt.maximumRounds {
            let data = try await send(messages, to: url, round: round)
            switch try OpenAICompatiblePayload.step(from: data) {
            case .answer(let answer):
                AppLog.estimation.info(
                    "resolved a line in \(round) round(s): \(answer.items.count) items from \(pool.count) candidates"
                )
                return DrivenLine(answer: answer, pool: pool)
            case .searches(let turn, let calls):
                // One message per call rather than one carrying them all, which is the
                // other difference in the shape of the conversation: a tool result is a
                // turn of its own here and a block of the user's turn there.
                let answers = await results(for: calls, pool: &pool)
                messages.append(turn)
                messages.append(contentsOf: answers)
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
    private func send(_ messages: [JSONValue], to url: URL, round: Int) async throws -> Data {
        let body = try OpenAICompatiblePayload.body(
            model: settings.model, messages: messages, searchesProducts: searcher.searchesProducts
        )
        let request = OpenAICompatiblePayload.request(url: url, key: key, body: body)
        let host = Self.host(of: url)
        let started = Date()
        let (data, response) = try await transport.fetch(request, host: host)
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.estimation.info(
            "\(host, privacy: .public) answered \(response.statusCode) in \(milliseconds) ms, round \(round)"
        )
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            guard !OpenAICompatiblePayload.rejectsTools(status: response.statusCode, body: data) else {
                AppLog.estimation.error("\(host, privacy: .public) will not call tools")
                throw EstimationError.unavailable(OpenAICompatiblePayload.toolsUnsupported)
            }
            throw OpenAICompatiblePayload.error(status: response.statusCode, body: data)
        }
        guard data.count <= OpenAICompatiblePayload.maximumBodySize else {
            AppLog.estimation.error("\(host, privacy: .public) answered \(data.count) bytes, too many for a reply")
            throw EstimationError.failed("the endpoint's answer was too large to read.")
        }
        return data
    }

    /// Runs what the model asked for and keeps the rows, in the order it asked.
    ///
    /// **One search at a time**, for the reason the other driver states: the searches
    /// mutate one pool, and numbering them in a fixed order is what makes the same line
    /// resolve the same way twice. It matters a little more here, because this path can no
    /// longer send `temperature: 0` and the ordering is the determinism it has left.
    ///
    /// Every call is answered, including one naming a tool this app does not have. A
    /// `tool_calls` entry left without a message carrying its id makes the next request
    /// invalid, so an unknown name gets a sentence saying so rather than silence — and a
    /// sentence is all it can get, there being no error flag on a tool message in this
    /// protocol.
    private func results(
        for calls: [OpenAICompatiblePayload.ToolCall], pool: inout LineCandidatePool
    ) async -> [JSONValue] {
        var results: [JSONValue] = []
        for call in calls {
            switch call.tool {
            case LinePrompt.foodTool:
                let found = pool.add(foods: await searcher.foods(matching: call.term))
                results.append(
                    OpenAICompatiblePayload.toolResult(id: call.id, text: LinePrompt.results(found))
                )
            case LinePrompt.productTool where searcher.searchesProducts:
                let found = pool.add(products: await searcher.products(matching: call.term))
                results.append(
                    OpenAICompatiblePayload.toolResult(id: call.id, text: LinePrompt.results(found))
                )
            default:
                AppLog.estimation.info("asked for a tool this app does not have")
                results.append(
                    OpenAICompatiblePayload.toolResult(
                        id: call.id,
                        text: LinePrompt.noSuchSearch
                    )
                )
            }
        }
        return results
    }

    /// What the log and the sentences call this path's endpoint: the user's own address.
    private nonisolated static func host(of url: URL) -> String {
        TransportFailure.host(of: url, fallback: "the endpoint")
    }
}
