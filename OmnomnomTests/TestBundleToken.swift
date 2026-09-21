import Foundation

/// Anchor for `Bundle(for:)` so tests can find fixtures in the test bundle.
/// Swift Testing suites are structs, so a class is needed for the lookup.
nonisolated final class TestBundleToken {}

nonisolated enum Fixtures {
    static var bundle: Bundle { Bundle(for: TestBundleToken.self) }

    static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
