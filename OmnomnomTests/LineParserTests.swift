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

    @Test func bothAndAndWithJoinAList() {
        // A food joined to another food is two foods, however it was joined.
        #expect(parse("oats and banana").map(\.name) == ["oats", "banana"])
        #expect(parse("toast with butter").map(\.name) == ["toast", "butter"])
    }

    @Test func theReportedLineBecomesOneRowPerFood() {
        // The line that found the bug: as one composite fragment "yogurt with bananas"
        // searched for a row holding both words, matched nothing and blocked the log.
        // Each part matches on its own, so each part is its own row.
        let items = parse("yogurt with bananas, seeds, peanuts")
        #expect(items.map(\.name) == ["yogurt", "bananas", "seeds", "peanuts"])
        #expect(items.map(\.lookupTerm) == ["yogurt", "bananas", "seeds", "peanuts"])
    }

    @Test func theLookupTermDropsFillerTheNameKeeps() {
        // Two fields because they want two things: the name is read by a person, the term
        // is anded together by an index that holds folded words and no "my".
        let item = try! #require(parse("a bowl of my Müsli").first)
        #expect(item.name == "my Müsli")
        #expect(item.lookupTerm == "musli")
    }

    @Test func theLongLineSplitsIntoFour() {
        let items = parse("a pancake with oats, peanut butter and banana")
        #expect(items.map(\.name) == ["pancake", "oats", "peanut butter", "banana"])
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
        // People write it this way and mean a big portion. Dropping it would lose the only
        // thing the line said about the amount, so it lands on the food it follows.
        let items = parse("chicken curry with rice, big portion")
        #expect(items.map(\.name) == ["chicken curry", "rice"])
        #expect(items.first?.size == nil)
        #expect(items.last?.size == .more)
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
        #expect(parse("Haferflocken mit Banane und Kaffee").map(\.name) == ["Haferflocken", "Banane", "Kaffee"])
    }

    @Test func aGermanLineNamingItsPartsBecomesThree() {
        let items = parse("brot mit erdnussmus und quark")
        #expect(items.map(\.name) == ["brot", "erdnussmus", "quark"])
    }

    @Test func aFrenchLineNamingItsPartsBecomesTwo() {
        // "avec" separates, and "du" is still only a connector, so neither survives into
        // a name.
        #expect(parse("du pain avec du beurre").map(\.name) == ["pain", "beurre"])
    }

    @Test func aConnectiveOpeningAFragmentIsStillDropped() {
        // A separator needs a space on either side, so the comma split leaves "with
        // berries" for the connector list to clean up.
        #expect(parse("porridge, with berries").map(\.name) == ["porridge", "berries"])
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
