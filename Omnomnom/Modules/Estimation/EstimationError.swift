import Foundation
import FoundationModels

/// Why an estimate could not be produced, each with a sentence for the sheet.
nonisolated enum EstimationError: Error, Hashable, Sendable, LocalizedError {
    /// The model is not usable; the reason is `EstimationAvailability.message` or the framework's.
    case unavailable(String)
    /// A photo was given on a system without image prompts (iOS 26).
    case photoUnavailable
    /// The user cancelled while the model was working.
    case cancelled
    /// The safety guardrails or the model itself declined the request.
    case guardrail
    /// The description was too long for the context window.
    case tooLong
    /// Anything else, with the framework's own words.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .photoUnavailable: "Photos need iOS 27. Describe the meal in words instead."
        case .cancelled: "Cancelled."
        case .guardrail: "The on-device model declined this request. Try a plainer description of the food."
        case .tooLong: "The description is too long for the on-device model. Shorten it and try again."
        case .failed(let message): "Estimation failed: \(message)"
        }
    }

    /// Maps what the session throws; everything undocumented keeps its own description.
    static func map(_ error: any Error) -> EstimationError {
        if let error = error as? EstimationError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? LanguageModelSession.GenerationError {
            return map(generation: error)
        }
        if #available(iOS 27, *), let error = error as? LanguageModelError {
            return map(model: error)
        }
        return .failed(error.localizedDescription)
    }

    private static func map(generation error: LanguageModelSession.GenerationError) -> EstimationError {
        switch error {
        case .exceededContextWindowSize:
            .tooLong
        case .guardrailViolation, .refusal:
            .guardrail
        case .assetsUnavailable:
            .unavailable("The on-device model is not available right now. Try again later.")
        case .rateLimited:
            .failed("too many requests; try again in a moment.")
        case .unsupportedLanguageOrLocale:
            .failed("the on-device model does not support this language.")
        case .decodingFailure:
            .failed("the model's answer could not be read. Try again.")
        default:
            .failed(error.localizedDescription)
        }
    }

    /// The framework's newer error on iOS 27; the session may throw either.
    @available(iOS 27, *)
    private static func map(model error: LanguageModelError) -> EstimationError {
        switch error {
        case .contextSizeExceeded:
            .tooLong
        case .guardrailViolation, .refusal:
            .guardrail
        case .rateLimited:
            .failed("too many requests; try again in a moment.")
        case .unsupportedLanguageOrLocale:
            .failed("the on-device model does not support this language.")
        case .timeout:
            .failed("the model took too long. Try again.")
        default:
            .failed(error.localizedDescription)
        }
    }
}
