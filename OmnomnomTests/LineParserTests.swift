import Foundation
import Testing
@testable import Omnomnom

/// Reading a typed line without a language model, which is the path every device has.
///
/// Expectations were settled by running the same rules over the real lines below rather
/// than by choosing what looked plausible. Three of them came from that: a number glued
/// to its unit, a container leaving a stranded "of", and a size word that belongs to the
/// food before it.
struct LineParserTests {
    private func parse(_ line: String) -> [ParsedItem] {
        LineParser.parse(line)
    }

    // MARK: - The common case

    @Test func aCommaSeparatedListIsOneItemEach() {
        let items = parse("oats, banana, coffee")
        #expect(items.map(\.name) == ["oats", "banana", "coffee"])
        #expect(items.allSatisfy { $0.amount == nil && $0.count == nil })
    }

    @Test func andJoinsAListAndWithDoesNot() {
        // "with" holding a fragment together is what lets the matcher try a composite
        // row before it splits anything.
        #expect(parse("oats and banana").map(\.name) == ["oats", "banana"])
        #expect(parse("toast with butter").map(\.name) == ["toast with butter"])
    }

    @Test func theLookupTermDropsFillerTheNameKeeps() {
        // Two fields because they want two things: the name is read by a person, the
        // term is anded together by an index where a row holding no "with" would miss.
        let item = try! #require(parse("toast with butter").first)
        #expect(item.name == "toast with butter")
        #expect(item.lookupTerm == "toast butter")
    }

    @Test func theLongLineSplitsIntoThree() {
        let items = parse("a pancake with oats, peanut butter and banana")
        #expect(items.map(\.name) == ["pancake with oats", "peanut butter", "banana"])
        #expect(items.first?.count == 1)
    }

    // MARK: - Quantities

    @Test func aLeadingNumberIsACount() {
        let items = parse("2 eggs")
        #expect(items.first?.name == "eggs")
        #expect(items.first?.count == 2)
        #expect(items.first?.amount == nil)
    }

    @Test func aSpelledNumberIsTheSameCount() {
        #expect(parse("two eggs").first?.count == 2)
    }

    @Test func anArticleMeansOne() {
        #expect(parse("a banana").first?.count == 1)
        #expect(parse("a banana").first?.name == "banana")
    }

    @Test func aNumberWithAUnitIsAnExplicitAmount() {
        let item = try! #require(parse("200 g chicken breast").first)
        #expect(item.name == "chicken breast")
        #expect(item.amount == 200)
        #expect(item.measure == .mass)
        #expect(item.count == nil)
    }

    @Test func aNumberGluedToItsUnitIsStillAnAmount() {
        // How people actually type it.
        let item = try! #require(parse("200g rice").first)
        #expect(item.name == "rice")
        #expect(item.amount == 200)
        #expect(item.measure == .mass)
    }

    @Test func volumeUnitsConvertToMillilitres() {
        let item = try! #require(parse("0.5 l milk").first)
        #expect(item.name == "milk")
        #expect(item.amount == 500)
        #expect(item.measure == .volume)
    }

    @Test func aSizeWordBecomesAStep() {
        let item = try! #require(parse("large coffee").first)
        #expect(item.name == "coffee")
        #expect(item.size == .more)
    }

    @Test func aContainerGoesAndTakesItsConnectorWithIt() {
        // "2 slices of bread" must not read back as "of bread".
        let items = parse("two slices of bread and a large coffee")
        #expect(items.map(\.name) == ["bread", "coffee"])
        #expect(items.first?.count == 2)
        #expect(items.last?.size == .more)
    }

    @Test func aBowlIsAContainerNotAFood() {
        let item = try! #require(parse("a big bowl of porridge").first)
        #expect(item.name == "porridge")
        #expect(item.size == .more)
    }

    @Test func aSizeOnItsOwnBelongsToTheFoodBeforeIt() {
        // People write it this way and mean the curry was big. Dropping it would lose
        // the only thing the line said about the amount.
        let items = parse("chicken curry with rice, big portion")
        #expect(items.count == 1)
        #expect(items.first?.name == "chicken curry with rice")
        #expect(items.first?.size == .more)
    }

    @Test func aSizeOnItsOwnWithNothingBeforeItIsDropped() {
        #expect(parse("big portion").isEmpty)
    }

    @Test func aSizeDoesNotOverrideOneTheFoodAlreadyHad() {
        let items = parse("small coffee, big portion")
        #expect(items.first?.size == .less)
    }

    // MARK: - Nothing to read

    @Test func aQuantityWithNoFoodIsNotAnItem() {
        #expect(parse("2").isEmpty)
        #expect(parse("a large").isEmpty)
        #expect(parse("   ").isEmpty)
        #expect(parse("").isEmpty)
    }

    @Test func aLineIsReadInGermanToo() {
        #expect(parse("Haferflocken mit Banane und Kaffee").map(\.name) == ["Haferflocken mit Banane", "Kaffee"])
    }

    @Test func aVeryLongLineIsCappedRatherThanRefused() {
        let long = Array(repeating: "oats", count: 400).joined(separator: ", ")
        #expect(!parse(long).isEmpty)
        #expect(parse(long).count < 400)
    }

    // MARK: - The fragment reader

    @Test func readKeepsASizeOnlyFragment() {
        #expect(LineParser.read("big portion") == .size(.more))
        #expect(LineParser.read("2") == .nothing)
        if case .food(let item) = LineParser.read("oats") {
            #expect(item.name == "oats")
        } else {
            Issue.record("expected a food")
        }
    }

    @Test func gluedAmountOnlySplitsDigitsFollowedByLetters() {
        #expect(LineParser.gluedAmount("200g")?.number == 200)
        #expect(LineParser.gluedAmount("200g")?.unit == "g")
        #expect(LineParser.gluedAmount("0.5l")?.number == 0.5)
        #expect(LineParser.gluedAmount("oats") == nil)
        #expect(LineParser.gluedAmount("200") == nil)
        #expect(LineParser.gluedAmount("g200") == nil)
    }
}
