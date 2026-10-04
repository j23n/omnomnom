import Foundation
import os

/// Runs one request against an OpenAI-compatible chat-completions endpoint.
///
/// The counterpart of `FoundationMealEstimator`, asked for the same thing with the same
/// instructions, so a draft reads the same whichever backend produced it. One request per
/// call, nothing kept between calls, no conversation: this is a single question with a
/// structured answer, not a chat.
///
/// Configuration is injected rather than read here. The endpoint lives in `UserDefaults`
/// and the key in the keychain, and an actor that reached for both could not be tested
/// and would read the keychain on whatever thread it happened to be running on. The
/// caller resolves them once and hands them over.
actor RemoteMealEstimator: MealEstimating {
    private let settings: RemoteEstimatorSettings
    private let key: String?
    private let transport: any HTTPTransport

    /// `transport` is the same one-request seam the barcode client uses. Its method is
    /// named for a GET, but all it does is hand a finished `URLRequest` to a session, so a
    /// POST goes through it unchanged and a test can answer without a network.
    init(
        settings: RemoteEstimatorSettings,
        key: String?,
        transport: any HTTPTransport = URLSessionTransport(timeout: RemoteEstimatePayload.timeout)
    ) {
        self.settings = settings
        self.key = key
        self.transport = transport
    }

    func estimate(_ input: EstimationInput) async throws -> MealEstimate {
        guard settings.isUsable, let url = settings.completionsURL else {
            throw EstimationError.unavailable("Set your endpoint's address and model in Settings first.")
        }
        let content = try RemoteEstimatePayload.content(for: input, sendsPhotos: settings.sendsPhotos)
        do {
            return try await send(content, to: url, mode: .strict)
        } catch StrictAttemptRefused.retryPlainly {
            AppLog.estimation.info(
                "\(Self.host(of: url), privacy: .public) refused the schema; asking again for plain JSON"
            )
            return try await send(content, to: url, mode: .plain)
        }
    }

    /// One request and one answer. Throws `EstimationError`, or `StrictAttemptRefused`
    /// when a strict attempt was turned down for the way it was phrased rather than for
    /// what it asked about.
    private func send(
        _ content: RemoteEstimateContent, to url: URL, mode: RemoteEstimateMode
    ) async throws -> MealEstimate {
        let body = try RemoteEstimatePayload.body(model: settings.model, mode: mode, content: content)
        let request = RemoteEstimatePayload.request(url: url, key: key, body: body)
        let host = Self.host(of: url)
        let started = Date()
        let (data, response) = try await fetch(request, host: host)
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.estimation.info(
            "\(host, privacy: .public) answered \(response.statusCode) in \(milliseconds) ms"
        )
        guard !Task.isCancelled else { throw EstimationError.cancelled }
        guard (200..<300).contains(response.statusCode) else {
            if mode == .strict, RemoteEstimatePayload.rejectsStrictRequest(status: response.statusCode, body: data) {
                throw StrictAttemptRefused.retryPlainly
            }
            throw RemoteEstimatePayload.error(status: response.statusCode, body: data)
        }
        guard data.count <= RemoteEstimatePayload.maximumBodySize else {
            AppLog.estimation.error(
                "\(host, privacy: .public) answered \(data.count) bytes, too many for an estimate"
            )
            throw EstimationError.failed("the endpoint's answer was too large to be an estimate.")
        }
        let answer: RemoteCompletionResponse
        do {
            answer = try JSONDecoder().decode(RemoteCompletionResponse.self, from: data)
        } catch {
            throw EstimationError.failed(RemoteEstimatePayload.unreadableAnswer)
        }
        // A model that declines says so in its own field on newer endpoints and in
        // `finish_reason` on the rest; either way it is the same refusal the on-device
        // guardrail produces, and the sheet already has words for that one.
        if let refusal = answer.refusal, !refusal.isEmpty { throw EstimationError.guardrail }
        if answer.finishReason == "content_filter" { throw EstimationError.guardrail }
        guard let reply = answer.content, !reply.isEmpty else {
            throw EstimationError.failed("the endpoint answered without an estimate.")
        }
        let estimate: MealEstimate
        do {
            estimate = try RemoteEstimatePayload.estimate(from: reply)
        } catch {
            // An answer cut off at the token limit is half a JSON object, which fails to
            // parse for a reason the user can do something about: their server's output
            // limit, not their description.
            guard answer.finishReason != "length" else {
                throw EstimationError.failed(
                    "the endpoint stopped before the estimate was finished; its reply limit may be very small."
                )
            }
            throw error
        }
        AppLog.estimation.info("remote estimate: \(estimate.items.count) items")
        return estimate
    }

    /// The request, with every transport failure already in the user's terms.
    private func fetch(_ request: URLRequest, host: String) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            // The code and nothing else: a URL error's description carries the address it
            // was given, and an address a user pasted can have a credential in it.
            AppLog.estimation.error(
                "\(host, privacy: .public) did not answer: \((error as? URLError)?.code.rawValue ?? 0)"
            )
            throw Self.mapped(error, host: host)
        }
    }

    /// What the log calls the endpoint. The host alone: a path can hold a key.
    private nonisolated static func host(of url: URL) -> String {
        url.host() ?? "the endpoint"
    }

    /// Transport failures in the user's terms. Each of these is a different thing to go
    /// and fix, and "Estimation failed: The request timed out." says which one it was far
    /// less clearly than naming the host does.
    private nonisolated static func mapped(_ error: any Error, host: String) -> EstimationError {
        guard let error = error as? URLError else { return EstimationError.map(error) }
        switch error.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .failed("\(host) did not answer in time. Try again.")
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .failed("there is no connection to \(host) right now.")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .failed("\(host) could not be reached. Check the address in Settings.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return .failed("the connection to \(host) is not trusted.")
        case .appTransportSecurityRequiresSecureConnection:
            return .failed("\(host) was asked for over http, which iOS will not allow. Use https.")
        default:
            return .failed("the request to \(host) failed.")
        }
    }
}

/// Carries one fact out of a failed strict attempt: the endpoint objected to the schema or
/// the temperature, so the same question is worth asking in plainer terms. Never reaches
/// the user, who could do nothing with it.
private nonisolated enum StrictAttemptRefused: Error {
    case retryPlainly
}
