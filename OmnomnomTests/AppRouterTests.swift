import Foundation
import Testing
@testable import Omnomnom

/// The slot an app intent leaves a line in.
///
/// These covered a second slot holding a food, which the intent behind visual intelligence
/// filled. That intent is gone and the camera belongs to the composer now, so the slot went
/// with it; the line slot is what Siri still writes and what the composer still reads.
@MainActor
struct AppRouterTests {
    @Test func aLineWaitsUntilItIsTaken() {
        let router = AppRouter()
        #expect(router.pendingLine == nil)
        router.compose("oats and a banana")
        #expect(router.pendingLine == "oats and a banana")
        router.clearPendingLine()
        #expect(router.pendingLine == nil)
    }

    @Test func aSecondLineReplacesOneNobodyActedOn() {
        // Replaced rather than queued: a line nobody has looked at is not worth keeping
        // ahead of the one just spoken.
        let router = AppRouter()
        router.compose("oats and a banana")
        router.compose("rice and chicken")
        #expect(router.pendingLine == "rice and chicken")
    }
}
