import Foundation

/// What a failed request to a remote estimator becomes, in the user's terms.
///
/// One copy for both remote paths. It was two, byte for byte, until the copies drifted:
/// the OpenAI-compatible one grew a sentence for a base URL typed as `http`, which iOS
/// refuses outright, and the Anthropic one answered that with the generic "the request
/// failed". Each of these is a different thing to go and fix, and "Estimation failed: The
/// request timed out." says which one it was far less clearly than naming the host does.
nonisolated enum TransportFailure {
    /// What the log and the sentence call the endpoint. The host alone: a path can hold a
    /// key. The fallback differs between the two paths because one address is the user's
    /// own and the other is Anthropic's.
    static func host(of url: URL, fallback: String) -> String {
        url.host() ?? fallback
    }

    static func mapped(_ error: any Error, host: String) -> EstimationError {
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

extension HTTPTransport {
    /// Sends, and turns a transport failure into a sentence naming the host.
    ///
    /// Named apart from `send(_:)` so the requirement and this are never two readings of
    /// one call: this one is the only thing either estimator calls.
    func fetch(_ request: URLRequest, host: String) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await send(request)
        } catch {
            // The code and nothing else: a URL error's description carries the address it
            // was given, and an address a user pasted can have a credential in it.
            AppLog.estimation.error(
                "\(host, privacy: .public) did not answer: \((error as? URLError)?.code.rawValue ?? 0)"
            )
            throw TransportFailure.mapped(error, host: host)
        }
    }
}
