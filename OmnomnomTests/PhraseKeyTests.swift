import Foundation
import Testing
@testable import Omnomnom

/// Filing a typed line so that retyping it reaches the same record.
///
/// Every expectation here was checked against the real wordings before it was written.
/// The two that matter: a line reaches one key however it is worded, and two counts of
/// the same food stay apart.
struct PhraseKeyTests {
    @Test func oneMealReachesOneKeyHoweverItIsWorded() {
        let wordings = [
            "oats with a banana",
            "Banana and oats!",
            "oats, banana",
            "  BANANA   OATS  ",
        ]
        let keys = Set(wordings.compactMap(PhraseKey.normalise))
        #expect(keys == ["banana oats"])
    }

    @Test func theLongLineAlsoReachesOneKey() {
        let first = PhraseKey.normalise("a pancake with oats, peanut butter and banana")
        let second = PhraseKey.normalise("Pancake, banana, peanut butter, oats")
        #expect(first == second)
        #expect(first == "banana butter oats pancake peanut")
    }

    @Test func wordOrderCarriesNoMeaning() {
        // Deliberate: they are one meal. The cost is that two genuinely different
        // meals could collapse into one key, which a visible, correctable recall
        // is what makes survivable.
        #expect(PhraseKey.normalise("chicken with rice") == PhraseKey.normalise("rice with chicken"))
    }

    @Test func howACountIsSpelledDoesNotSplitAPhrase() {
        #expect(PhraseKey.normalise("two eggs") == PhraseKey.normalise("2 eggs"))
        #expect(PhraseKey.normalise("two eggs") == "2 eggs")
    }

    @Test func differentCountsAreDifferentPhrases() {
        // Each remembers its own amount, which is the whole reason quantities are kept
        // rather than stripped.
        #expect(PhraseKey.normalise("2 eggs") != PhraseKey.normalise("3 eggs"))
    }

    @Test func decimalsKeepTheirPoint() {
        #expect(PhraseKey.normalise("0.5 l milk") == "0.5 l milk")
    }

    @Test func aTrailingFullStopIsPunctuationNotAPoint() {
        #expect(PhraseKey.normalise("oats.") == PhraseKey.normalise("oats"))
    }

    @Test func fillerWordsGoInThreeLanguages() {
        #expect(PhraseKey.normalise("ein Brot mit Butter") == PhraseKey.normalise("brot butter"))
        #expect(PhraseKey.normalise("du pain avec du beurre") == PhraseKey.normalise("pain beurre"))
        #expect(PhraseKey.normalise("some of my oats") == PhraseKey.normalise("oats"))
    }

    @Test func diacriticsAndCaseAreIgnored() {
        #expect(PhraseKey.normalise("Käse") == PhraseKey.normalise("kase"))
        #expect(PhraseKey.normalise("CRÈME") == PhraseKey.normalise("creme"))
    }

    @Test func aLineWithNoFoodInItHasNoKey() {
        // Nothing to remember, so nothing is filed.
        for line in ["and some of my", "...", "   ", "!!!", ""] {
            #expect(PhraseKey.normalise(line) == nil)
        }
    }

    @Test func tokensKeepTypedOrderWhileTheKeySorts() {
        // The parser splits on the same notion of a word, so the two cannot drift.
        #expect(PhraseKey.tokens("oats with a banana") == ["oats", "banana"])
        #expect(PhraseKey.normalise("oats with a banana") == "banana oats")
    }

    @Test func aRepeatedWordDoesNotChangeTheKeyTwice() {
        // Sorted and joined, so "egg egg" keys differently from "egg": two of a thing
        // is not the same line as one of it.
        #expect(PhraseKey.normalise("egg egg") == "egg egg")
        #expect(PhraseKey.normalise("egg") == "egg")
    }
}
