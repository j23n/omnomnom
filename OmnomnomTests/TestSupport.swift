import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
@testable import Omnomnom

/// Anchor for `Bundle(for:)` so tests can find fixtures in the test bundle.
/// Swift Testing suites are structs, so a class is needed for the lookup.
nonisolated final class TestBundleToken {}

nonisolated enum Fixtures {
    static var bundle: Bundle { Bundle(for: TestBundleToken.self) }

    static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }

    /// A `width` x `height` image with a flat colour, encoded as PNG through ImageIO.
    ///
    /// Only the dimensions matter to any caller — the photo paths are tested on what they
    /// do with a size, never on what the picture is of — so the colour is arbitrary and
    /// the three suites that each built one of these share this.
    static func pngData(width: Int, height: Int) -> Data? {
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
}

/// An empty in-memory store on the app's own schema.
///
/// Six suites built this by hand, in two spellings of the same three lines. `StoreSchema`
/// was centralised because the app, the previews and the tests each carrying their own
/// copy of the schema is "a footgun with a delay on it"; the container around it is the
/// other half of that, and this is where it lives.
enum TestStore {
    static func context() throws -> ModelContext {
        let schema = StoreSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }
}
