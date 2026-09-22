import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Omnomnom

struct PhotoDataTests {
    /// A `width` x `height` image with a flat colour, encoded as PNG through ImageIO.
    private func pngData(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    @Test func storedPhotoIsAJPEGNoLargerThanTheStoredSize() throws {
        let png = try #require(pngData(width: 2000, height: 1000))
        let stored = try #require(PhotoData.stored(from: png))
        #expect(stored.count >= 2)
        #expect(stored[stored.startIndex] == 0xFF)
        #expect(stored[stored.startIndex + 1] == 0xD8)
        let decoded = try #require(PhotoData.downscaled(stored, maxPixelSize: 4096))
        #expect(decoded.width == PhotoData.storedPixelSize)
        #expect(decoded.height == PhotoData.storedPixelSize / 2)
    }

    @Test func aSmallImageIsNotEnlarged() throws {
        let png = try #require(pngData(width: 300, height: 200))
        let stored = try #require(PhotoData.stored(from: png))
        let decoded = try #require(PhotoData.downscaled(stored, maxPixelSize: 4096))
        #expect(decoded.width == 300)
        #expect(decoded.height == 200)
    }

    @Test func downscaledCapsTheLongSide() throws {
        let png = try #require(pngData(width: 2000, height: 1000))
        let thumbnail = try #require(PhotoData.downscaled(png, maxPixelSize: 320))
        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 160)
    }

    @Test func dataThatIsNotAnImageIsRefused() {
        #expect(PhotoData.stored(from: Data("nope".utf8)) == nil)
        #expect(PhotoData.downscaled(Data("nope".utf8), maxPixelSize: 100) == nil)
        #expect(PhotoData.stored(from: Data()) == nil)
    }
}
