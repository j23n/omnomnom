import Foundation
import Testing
@testable import Omnomnom

/// The mapping the sheet relies on, without a model: own errors pass through,
/// cancellation is recognised, and anything else keeps its words.
struct EstimationErrorTests {
    @Test func ownErrorsPassThrough() {
        #expect(EstimationError.map(EstimationError.tooLong) == .tooLong)
        #expect(EstimationError.map(EstimationError.unavailable("off")) == .unavailable("off"))
    }

    @Test func cancellationIsRecognised() {
        #expect(EstimationError.map(CancellationError()) == .cancelled)
    }

    @Test func unknownErrorsKeepTheirDescription() {
        let mapped = EstimationError.map(URLError(.timedOut))
        guard case .failed(let message) = mapped else {
            Issue.record("expected failed, got \(mapped)")
            return
        }
        #expect(!message.isEmpty)
        #expect(mapped.errorDescription?.hasPrefix("Estimation failed:") == true)
    }

    @Test func everyCaseHasASentence() {
        let cases: [EstimationError] = [.unavailable("x"), .photoUnavailable, .cancelled, .guardrail, .tooLong, .failed("y")]
        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        #expect(EstimationError.photoUnavailable.errorDescription?.contains("iOS 27") == true)
    }
}
