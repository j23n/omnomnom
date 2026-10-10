import Foundation
import Testing
@testable import Omnomnom

/// What kind of day the app is looking at, which is what makes an average defensible.
struct DayStateTests {
    @Test func noEntriesIsEmptyWhateverTheUserMarked() {
        #expect(DayState.derive(entryOrigins: [], markedComplete: false) == .empty)
        #expect(DayState.derive(entryOrigins: [], markedComplete: true) == .empty)
    }

    @Test func entriesWithoutAMarkArePartial() {
        #expect(DayState.derive(entryOrigins: [.typed, .picked], markedComplete: false) == .partial)
    }

    @Test func aMarkedDayIsComplete() {
        #expect(DayState.derive(entryOrigins: [.typed], markedComplete: true) == .complete)
    }

    @Test func aDayEntirelyFromABaselineIsAssumed() {
        #expect(DayState.derive(entryOrigins: [.baseline, .baseline], markedComplete: false) == .assumed)
    }

    @Test func assumedBeatsCompleteDeliberately() {
        // A day accepted in one tap must not read as one someone described, however they
        // marked it afterwards. One tap is cheap enough that it stops being an assertion.
        #expect(DayState.derive(entryOrigins: [.baseline], markedComplete: true) == .assumed)
    }

    @Test func oneDescribedEntryIsEnoughToStopItBeingAssumed() {
        #expect(DayState.derive(entryOrigins: [.baseline, .typed], markedComplete: false) == .partial)
        #expect(DayState.derive(entryOrigins: [.baseline, .typed], markedComplete: true) == .complete)
    }

    @Test func everyStateHasSomethingToSayAndNoneOfItIsAShare() {
        for state in DayState.allCases {
            #expect(!state.note.isEmpty)
            // Coverage is named, never divided. A note describes a state, so it carries
            // no percentage and no figure of any kind — a count is one formatting
            // decision away from a score.
            #expect(!state.note.contains("%"))
            let holdsAFigure = state.note.contains(where: \.isNumber)
            #expect(!holdsAFigure)
        }
    }
}
