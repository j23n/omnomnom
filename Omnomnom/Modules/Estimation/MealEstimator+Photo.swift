import Foundation
import FoundationModels

/// The photo tier: the same instructions and structure, with the image attached to the
/// prompt. This is the only file that uses the iOS 27 image-prompt API, so a signature
/// change on a first build stays contained here.
@available(iOS 27, *)
extension FoundationMealEstimator {
    /// Longest side of the image handed to the model, in pixels.
    nonisolated static let promptPixelSize = 1024

    /// Downscales the photo, attaches it after the text, and returns the model's estimate.
    func respond(session: LanguageModelSession, imageData: Data, text: String, options: GenerationOptions) async throws -> MealEstimate {
        guard let image = PhotoData.downscaled(imageData, maxPixelSize: Self.promptPixelSize) else {
            throw EstimationError.failed("the photo could not be read.")
        }
        let response = try await session.respond(generating: MealEstimate.self, options: options) {
            "\(text)"
            Attachment(image)
        }
        return response.content
    }
}
