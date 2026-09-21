import CoreGraphics
import Foundation
import ImageIO

/// Decodes a picked or captured photo into a downscaled `CGImage` through ImageIO,
/// applying the EXIF orientation so the model sees the plate the right way up. Runs
/// wherever it is called, never touches disk, and keeps nothing.
nonisolated enum EstimationImage {
    /// Longest side of the image handed to the model, in pixels.
    static let promptPixelSize = 1024
    /// Longest side of the thumbnail shown in the sheet.
    static let thumbnailPixelSize = 320

    /// The image at most `maxPixelSize` on its long side, or `nil` when the data is not an image.
    static func downscaled(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
