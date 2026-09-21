import Foundation
import FoundationModels
import os

/// What the user gave: words, or a photo with optional words. The photo is the raw
/// picked or captured file; the estimator downscales it before the model sees it.
nonisolated enum EstimationInput: Sendable {
    case text(String)
    case photo(Data, description: String?)
}

/// The estimator behind the sheet, so the UI can be driven without a model.
nonisolated protocol MealEstimating: Sendable {
    /// One request, one session. Throws `EstimationError` only.
    func estimate(_ input: EstimationInput) async throws -> MealEstimate
}

/// Runs one request against the on-device model. A session is created per request
/// with the fixed instructions and discarded; nothing is kept between calls. Greedy
/// sampling so the same input gives the same numbers. The photo path lives in
/// `MealEstimator+Photo`, the one place that touches the iOS 27 image API.
actor FoundationMealEstimator: MealEstimating {
    init() {}

    func estimate(_ input: EstimationInput) async throws -> MealEstimate {
        let session = LanguageModelSession(instructions: EstimationPrompt.instructions)
        let options = GenerationOptions(samplingMode: .greedy)
        do {
            switch input {
            case .text(let description):
                let response = try await session.respond(
                    to: EstimationPrompt.text(description: description),
                    generating: MealEstimate.self,
                    options: options
                )
                try Task.checkCancellation()
                AppLog.estimation.info("text estimate: \(response.content.items.count) items")
                return response.content
            case .photo(let data, let description):
                guard #available(iOS 27, *) else { throw EstimationError.photoUnavailable }
                let estimate = try await respond(
                    session: session, imageData: data,
                    text: EstimationPrompt.photoText(description: description), options: options
                )
                try Task.checkCancellation()
                AppLog.estimation.info("photo estimate: \(estimate.items.count) items")
                return estimate
            }
        } catch {
            let mapped = EstimationError.map(error)
            if mapped != .cancelled {
                AppLog.estimation.error("estimate failed: \(error.localizedDescription, privacy: .public)")
            }
            throw mapped
        }
    }
}
