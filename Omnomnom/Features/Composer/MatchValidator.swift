import Foundation
import FoundationModels
import os

/// Checking a retriever's choice, so the UI can be driven without a model.
nonisolated protocol MatchValidating: Sendable {
    /// One request for a whole line. Throws `EstimationError` only.
    func validate(line: String, items: [ValidationItem]) async throws -> MatchVerdicts
}

/// Asks the on-device model to choose among rows the database already found.
///
/// One request per line rather than per item, because the line is better context than
/// any fragment of it: "oats, banana, coffee" at eight in the morning disambiguates all
/// three together in a way none of them does alone, and it is one round trip instead of
/// three.
///
/// A session per request, discarded after, greedy sampling so the same line resolves the
/// same way twice. The same posture as the estimator, for the same reasons.
actor FoundationMatchValidator: MatchValidating {
    init() {}

    func validate(line: String, items: [ValidationItem]) async throws -> MatchVerdicts {
        guard !items.isEmpty else { return MatchVerdicts(verdicts: []) }
        let session = LanguageModelSession(instructions: ValidationPrompt.instructions)
        let options = GenerationOptions(samplingMode: .greedy)
        do {
            let response = try await session.respond(
                to: ValidationPrompt.text(line: line, items: items),
                generating: MatchVerdicts.self,
                options: options
            )
            try Task.checkCancellation()
            AppLog.estimation.info("validated \(response.content.verdicts.count) of \(items.count) items")
            return response.content
        } catch {
            let mapped = EstimationError.map(error)
            if mapped != .cancelled {
                AppLog.estimation.error("validation failed: \(error.localizedDescription, privacy: .public)")
            }
            throw mapped
        }
    }
}
