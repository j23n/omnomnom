import CoreGraphics
import Foundation
import Testing
@testable import Omnomnom

struct PhotoDataTests {
    @Test func storedPhotoIsAJPEGNoLargerThanTheStoredSize() throws {
        let png = try #require(Fixtures.pngData(width: 2000, height: 1000))
        let stored = try #require(PhotoData.stored(from: png))
        #expect(stored.count >= 2)
        #expect(stored[stored.startIndex] == 0xFF)
        #expect(stored[stored.startIndex + 1] == 0xD8)
        let decoded = try #require(PhotoData.downscaled(stored, maxPixelSize: 4096))
        #expect(decoded.width == PhotoData.storedPixelSize)
        #expect(decoded.height == PhotoData.storedPixelSize / 2)
    }

    @Test func aSmallImageIsNotEnlarged() throws {
        let png = try #require(Fixtures.pngData(width: 300, height: 200))
        let stored = try #require(PhotoData.stored(from: png))
        let decoded = try #require(PhotoData.downscaled(stored, maxPixelSize: 4096))
        #expect(decoded.width == 300)
        #expect(decoded.height == 200)
    }

    @Test func downscaledCapsTheLongSide() throws {
        let png = try #require(Fixtures.pngData(width: 2000, height: 1000))
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
