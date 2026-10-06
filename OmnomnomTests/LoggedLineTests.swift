import Foundation
import Testing
@testable import Omnomnom

/// What a send writes, what it asks about, and the sentence the way back is offered under.
struct LoggedLineTests {
    private func choice(_ name: String) -> FoodChoice {
        FoodChoice(
            source: .bundled(id: abs(name.hashValue % 10_000)),
            name: name,
            perUnit: Nutrition(energy: 100)
        )
    }

    private func row(
        _ name: String, matched: Bool = true, confidence: MatchConfidence = .settled,
        implausible: Bool = false
    ) -> ResolvedRow {
        ResolvedRow(
            name: name, choice: matched ? choice(name) : nil, amount: 100,
            origin: .database, confidence: confidence, implausible: implausible
        )
    }

    private func resolution(_ rows: [ResolvedRow], line: String = "oats, banana") -> LineResolution {
        LineResolution(line: line, rows: rows, wasChecked: true, meal: .breakfast)
    }

    // MARK: - What the screen gates on

    @Test func aSettledRowAndAProbableOneAreBothLoggable() {
        // A probable match is logged and marked, not held back: the matcher would defend
        // it, and the screen the user is looking at is where it gets corrected if it is
        // wrong.
        let line = resolution([
            row("Oat flakes"),
            row("Banana", confidence: .probable)
        ])
        #expect(line.canLog)
        #expect(line.blockingCount == 0)
        #expect(line.glanceCount == 1)
    }

    @Test func anUnsureMatchAndAnUnmatchedRowBothStopTheLog() {
        let line = resolution([
            row("Oat flakes"),
            row("something", matched: false),
            row("Rye bread", confidence: .unsure)
        ])
        #expect(!line.canLog)
        #expect(line.blockingCount == 2)
    }

    @Test func anImplausibleAmountIsWorthALookAndNotABlock() {
        // The model doubting a weight is a reason to mark the row, never a reason to
        // refuse what the person said they ate.
        let line = resolution([row("Olive oil", implausible: true)])
        #expect(line.canLog)
        #expect(line.glanceCount == 1)
    }

    @Test func anEmptyLineCannotBeLogged() {
        #expect(!resolution([]).canLog)
    }

    // MARK: - The offer

    @Test func oneItemIsSaidInTheSingular() {
        let logged = LoggedLine(line: "coffee", entryIDs: [UUID()], marked: 0, failed: 0)
        #expect(logged.message == "Logged 1 item.")
        #expect(logged.canUndo)
    }

    @Test func markedRowsAreCountedNotRatioed() {
        let logged = LoggedLine(
            line: "oats, banana, coffee", entryIDs: [UUID(), UUID(), UUID()], marked: 2, failed: 0
        )
        #expect(logged.message == "Logged 3 items. 2 want a look.")
        // Never "2 of 3": a count of things to look at is a fact, a proportion of a meal
        // is a verdict on it.
        #expect(!logged.message.contains("of 3"))
    }

    @Test func oneMarkedRowAgreesWithItsVerb() {
        let logged = LoggedLine(line: "oats", entryIDs: [UUID()], marked: 1, failed: 0)
        #expect(logged.message == "Logged 1 item. 1 wants a look.")
    }

    @Test func rowsThatFailedAreNamedAfterWhatWorked() {
        let logged = LoggedLine(line: "oats, x", entryIDs: [UUID()], marked: 0, failed: 1)
        #expect(logged.message == "Logged 1 item. 1 could not be logged.")
    }

    @Test func aSendThatWroteNothingOffersNoUndo() {
        let logged = LoggedLine(line: "x", entryIDs: [], marked: 0, failed: 2)
        #expect(logged.message == "Nothing could be logged from that line.")
        #expect(!logged.canUndo)
    }

    @Test func troubleFromTheRowsIsSaidOnceHoweverManyRowsHadIt() {
        let refused = "Logged here only. Health didn't accept it."
        let results = (0..<3).map { _ in
            LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil)
        }
        let outcome = LineLogOutcome(results: results, failed: 0, remembered: true)
        let logged = LoggedLine(resolution: resolution([row("Oat flakes")]), outcome: outcome)
        #expect(logged.message == "Logged 3 items. \(refused)")
    }

    @Test func theOfferCountsWhatReachedTheDayAndNotWhatTheLineNamed() {
        // Two rows went to the log and one of them could not be written, so the offer
        // says "logged 1" and names the other rather than reading "1 of 2", which would
        // be a figure about the line instead of about the day.
        let line = resolution([row("Oat flakes"), row("Rye bread")])
        let outcome = LineLogOutcome(
            results: [LogResult(entryID: UUID(), written: [.energy], healthError: nil, storeError: nil)],
            failed: 1,
            remembered: true
        )
        let logged = LoggedLine(resolution: line, outcome: outcome)
        #expect(logged.message == "Logged 1 item. 1 could not be logged.")
        #expect(logged.entryIDs.count == 1)
    }

    @Test func aMarkedRowReachesTheOfferFromTheLineItWroteFrom() {
        let line = resolution([row("Banana", confidence: .probable)])
        let outcome = LineLogOutcome(
            results: [LogResult(entryID: UUID(), written: [.energy], healthError: nil, storeError: nil)],
            failed: 0,
            remembered: true
        )
        let logged = LoggedLine(resolution: line, outcome: outcome)
        #expect(logged.marked == 1)
        #expect(logged.message == "Logged 1 item. 1 wants a look.")
    }

    // MARK: - What the undo was asked to take back

    @Test func nothingRemovedIsNothingToSay() {
        #expect(UndoOutcome(removed: 3, kept: 0).message == nil)
    }

    @Test func anEntryHealthWouldNotReleaseIsSaidPlainly() {
        #expect(UndoOutcome(removed: 0, kept: 1).message == "That entry could not be taken back.")
        #expect(
            UndoOutcome(removed: 0, kept: 2).message == "Those 2 entries could not be taken back."
        )
        #expect(UndoOutcome(removed: 2, kept: 1).message == "Took back 2. 1 is still on the day.")
        #expect(UndoOutcome(removed: 1, kept: 2).message == "Took back 1. 2 are still on the day.")
    }
}
