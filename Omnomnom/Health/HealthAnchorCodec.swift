import Foundation
import HealthKit
import os

/// Secure-coded bytes for `HKQueryAnchor`, so `HealthAnchors` can hold plain `Data`.
/// The only place an anchor object and its bytes meet.
nonisolated enum HealthAnchorCodec {
    static func encode(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    /// The anchor in `data`, or `nil` for no data or bytes that no longer decode, so a
    /// corrupt anchor means one full re-read of that type rather than a failure.
    static func decode(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            AppLog.health.error("anchor unreadable, reading full history: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
