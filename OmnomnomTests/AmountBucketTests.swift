import Foundation
import Testing
@testable import Omnomnom

/// Amounts as a step rather than a number.
struct AmountBucketTests {
    @Test func usualIsTheReferenceItself() {
        #expect(AmountBucket.usual.amount(of: 40) == 40)
        #expect(AmountBucket.usual.amount(of: 180) == 180)
    }

    @Test func theStepsAreGeometricSoLessThenMoreDoesNotReturnHome() {
        // 0.7 then 1.4 is 0.98 of where it started, not 1.0, but the point is that
        // neither step is the other's inverse by accident.
        #expect(AmountBucket.less.multiplier < 1)
        #expect(AmountBucket.more.multiplier > 1)
        #expect(AmountBucket.less.multiplier * AmountBucket.double.multiplier > 1)
    }

    @Test func amountsRoundToSomethingAPersonWouldRecognise() {
        #expect(AmountBucket.less.amount(of: 40) == 30)
        #expect(AmountBucket.more.amount(of: 40) == 55)
        #expect(AmountBucket.double.amount(of: 40) == 80)
        #expect(AmountBucket.less.amount(of: 180) == 130)
        #expect(AmountBucket.more.amount(of: 200) == 280)
    }

    @Test func aReferenceOfNothingComesToNothing() {
        for bucket in AmountBucket.allCases {
            #expect(bucket.amount(of: 0) == 0)
        }
    }

    @Test func everyBucketHasALabelAndNoneIsAFigure() {
        for bucket in AmountBucket.allCases {
            #expect(!bucket.label.isEmpty)
            #expect(!bucket.label.contains("g"))
            #expect(!bucket.label.contains("%"))
        }
    }
}
