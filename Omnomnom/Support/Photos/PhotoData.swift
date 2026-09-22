import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes a picked or captured photo through ImageIO, applying the EXIF orientation
/// so the plate is the right way up, and re-encodes it at the size the store keeps.
/// Runs wherever it is called and touches no disk; what is kept is the caller's choice.
nonisolated enum PhotoData {
    /// Longest side of a stored photo, in pixels: enough for the viewer, small enough
    /// that a year of meals stays a modest external-storage folder.
    static let storedPixelSize = 1024
    /// Cap on the long side of a row thumbnail decode.
    static let thumbnailPixelSize = 320
    /// JPEG quality of a stored photo.
    static let storedQuality = 0.7

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

    /// The bytes to store for a picked or captured file: decoded with its orientation
    /// applied, at most `storedPixelSize` on the long side, as a JPEG. `nil` when the
    /// data is not an image the device can read.
    static func stored(from data: Data) -> Data? {
        guard let image = downscaled(data, maxPixelSize: storedPixelSize) else { return nil }
        return jpegData(image, quality: storedQuality)
    }

    /// `image` encoded as a JPEG at `quality` (0 to 1), or `nil` when encoding fails.
    static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
