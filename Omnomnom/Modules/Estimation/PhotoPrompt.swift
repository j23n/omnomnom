import Foundation
import FoundationModels

#if compiler(>=6.4)
/// Attaching a photograph to an on-device prompt, which is an iOS 27 API.
///
/// The only place in the app that touches it, so a signature change on a first build is one
/// file's problem. It was the meal estimator's own extension while the estimator was the
/// only thing that sent a photograph; the line resolver now sends one too, down a different
/// path and generating a different shape, so the helper is generic over what it generates
/// and belongs to neither of them.
///
/// Both callers guard `#available(iOS 27, *)` themselves and answer `photoUnavailable`
/// below it, because what the user needs told at that point is about their OS rather than
/// about this call.
@available(iOS 27, *)
nonisolated enum PhotoPrompt {
    /// Longest side of the image handed to the model, in pixels.
    ///
    /// Not shared with the remote paths' own sizes, which are chosen against what a request
    /// costs: Anthropic's 1,024 is priced in visual tokens and an endpoint of one's own gets
    /// 768 for a phone connection. Nothing is charged here, so this is simply what the model
    /// reads a plate from.
    static let pixelSize = 1024

    /// Downscales the photograph, attaches it after the text, and returns what was generated.
    static func respond<Content: Generable>(
        session: LanguageModelSession, imageData: Data, text: String,
        generating: Content.Type, options: GenerationOptions
    ) async throws -> Content {
        guard let image = PhotoData.downscaled(imageData, maxPixelSize: pixelSize) else {
            throw EstimationError.failed(EstimationError.unreadablePhoto)
        }
        let response = try await session.respond(generating: generating, options: options) {
            "\(text)"
            Attachment(image)
        }
        return response.content
    }
}
#else

/// Built with Xcode 26, whose iOS 26 SDK has no image attachments (`OnDeviceSDK.swift`): a
/// photograph is answered as on a device below iOS 27, and only Xcode 27 builds read one.
@available(iOS 27, *)
nonisolated enum PhotoPrompt {
    static let pixelSize = 1024

    static func respond<Content: Generable>(
        session: LanguageModelSession, imageData: Data, text: String,
        generating: Content.Type, options: GenerationOptions
    ) async throws -> Content {
        throw EstimationError.photoUnavailable
    }
}
#endif
