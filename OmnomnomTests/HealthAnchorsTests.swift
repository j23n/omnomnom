import Foundation
import HealthKit
import Testing
@testable import Omnomnom

struct HealthAnchorsTests {
    @Test func jsonRoundTripKeepsEveryTypeAnchor() throws {
        var anchors = HealthAnchors.empty
        anchors["HKQuantityTypeIdentifierDietaryProtein"] = Data([1, 2, 3])
        anchors["HKCorrelationTypeIdentifierFood"] = Data([9])
        let decoded = try HealthAnchors(json: try anchors.encoded())
        #expect(decoded == anchors)
        #expect(decoded["HKQuantityTypeIdentifierDietaryProtein"] == Data([1, 2, 3]))
        #expect(decoded["HKQuantityTypeIdentifierDietaryEnergyConsumed"] == nil)
    }

    @Test func emptyContainerRoundTrips() throws {
        let decoded = try HealthAnchors(json: try HealthAnchors.empty.encoded())
        #expect(decoded == .empty)
        #expect(decoded.data.isEmpty)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            _ = try HealthAnchors(json: Data("not json".utf8))
        }
    }

    @Test func defaultsRoundTrip() throws {
        let suite = "HealthAnchorsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(HealthAnchors.load(from: defaults) == .empty)
        var anchors = HealthAnchors.empty
        anchors["HKQuantityTypeIdentifierDietarySodium"] = Data([4, 2])
        try anchors.save(to: defaults)
        #expect(HealthAnchors.load(from: defaults) == anchors)
        defaults.set(Data("{".utf8), forKey: HealthAnchors.defaultsKey)
        #expect(HealthAnchors.load(from: defaults) == .empty)
    }

    /// `HKQueryAnchor` needs no store, so the codec runs here too.
    @Test func queryAnchorSurvivesTheCodec() throws {
        let data = try HealthAnchorCodec.encode(HKQueryAnchor(fromValue: 42))
        #expect(!data.isEmpty)
        #expect(HealthAnchorCodec.decode(data) != nil)
        #expect(HealthAnchorCodec.decode(nil) == nil)
        #expect(HealthAnchorCodec.decode(Data([0, 1, 2])) == nil)
    }
}
