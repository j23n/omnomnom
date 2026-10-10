import Foundation
import Testing
@testable import Omnomnom

/// FTS5 expressions, including the plural problem that made the most ordinary breakfast
/// in the German table unreachable.
struct FoodQueryTests {
    @Test func oneTokenIsAQuotedPrefixTerm() {
        #expect(FoodQuery.ftsMatchExpression(for: "apple") == "\"apple\"*")
    }

    @Test func tokensAreAndedTogether() {
        #expect(FoodQuery.ftsMatchExpression(for: "peanut butter") == "\"peanut\"* AND \"butter\"*")
    }

    @Test func blankTextHasNoExpression() {
        #expect(FoodQuery.ftsMatchExpression(for: "") == nil)
        #expect(FoodQuery.ftsMatchExpression(for: "   ") == nil)
    }

    @Test func punctuationNeverReachesATerm() {
        // Quotes used to be doubled so a stray one could not close a term. They no longer
        // can: an expression is built from `words(of:)`, which splits on everything that
        // is not a letter or a number, so the quote is a separator and never a character
        // inside a term. Escaping it was dead code and this is the property that replaced it.
        #expect(FoodQuery.ftsMatchExpression(for: "6\" sub") == "\"6\"* AND \"sub\"*")
        #expect(FoodQuery.ftsMatchExpression(for: "yogurt, plain") == "\"yogurt\"* AND \"plain\"*")
        #expect(FoodQuery.ftsMatchExpression(for: "\"\"\"") == nil)
    }

    // MARK: - The head phrase

    @Test func aCommaEndsTheHeadPhrase() {
        // Table wording inverts the compound, so everything after the comma qualifies it.
        #expect(FoodQuery.headPhrase(of: "pasta, cooked") == ["pasta"])
        #expect(FoodQuery.headPhrase(of: "milk, semi-skimmed") == ["milk"])
        #expect(FoodQuery.headPhrase(of: "yogurt, natural") == ["yogurt"])
    }

    @Test func aPlainCompoundKeepsAllOfItsWords() {
        // Here the head is last, so neither word can be dropped and both are kept.
        #expect(FoodQuery.headPhrase(of: "wholemeal pasta, cooked") == ["wholemeal", "pasta"])
        #expect(FoodQuery.headPhrase(of: "rye bread") == ["rye", "bread"])
    }

    @Test func aPrepositionEndsTheHeadPhrase() {
        // What follows is a garnish on what came before: the measured failures were
        // *Chocolate* for a pain au chocolat and *Tomato raw* for a tin of baked beans.
        #expect(FoodQuery.headPhrase(of: "croissant with chocolate") == ["croissant"])
        #expect(FoodQuery.headPhrase(of: "baked beans in tomato sauce") == ["beans"])
        #expect(FoodQuery.headPhrase(of: "spaghetti with bolognese sauce") == ["spaghetti"])
    }

    @Test func preparationWordsDropOutRatherThanEndingThePhrase() {
        #expect(FoodQuery.headPhrase(of: "grilled chicken breast") == ["chicken", "breast"])
        #expect(FoodQuery.headPhrase(of: "cooked") == [])
    }

    @Test func aHeadPhraseIsCapped() {
        #expect(FoodQuery.headPhrase(of: "one two three four five") == ["one", "two", "three", "four"])
        #expect(FoodQuery.headPhrase(of: "one two three", limit: 2) == ["one", "two"])
    }

    @Test func nothingToReadIsAnEmptyPhrase() {
        #expect(FoodQuery.headPhrase(of: "") == [])
        #expect(FoodQuery.headPhrase(of: ", cooked") == [])
        #expect(FoodQuery.headPhrase(of: "with cheese") == [])
    }

    @Test func functionWordsAreRecognisedWhateverTheirCase() {
        #expect(FoodQuery.isFunctionWord("With"))
        #expect(FoodQuery.isFunctionWord("AND"))
        #expect(!FoodQuery.isFunctionWord("cheese"))
    }

    // MARK: - Plurals

    @Test func aPluralIsSearchedInBothForms() {
        // FTS5's prefix match runs forwards only: "oat"* finds "Oat flakes" and "oats"*
        // finds nothing. The German table calls the food "Oat flakes".
        #expect(FoodQuery.forms(of: "oats") == ["oats", "oat"])
        #expect(FoodQuery.ftsMatchExpression(for: "oats") == "(\"oats\"* OR \"oat\"*)")
    }

    @Test func anEsPluralDropsBothEndings() {
        #expect(FoodQuery.forms(of: "tomatoes") == ["tomatoes", "tomato", "tomatoe"])
    }

    @Test func aShortWordIsLeftAlone() {
        // "as", "is", "gas": dropping the s would search for a letter.
        #expect(FoodQuery.forms(of: "gas") == ["gas"])
        #expect(FoodQuery.forms(of: "as") == ["as"])
    }

    @Test func adoubleSIsNotAPlural() {
        #expect(FoodQuery.forms(of: "cress") == ["cress"])
        #expect(FoodQuery.forms(of: "glass") == ["glass"])
    }

    @Test func aSingularIsLeftAlone() {
        #expect(FoodQuery.forms(of: "oat") == ["oat"])
        #expect(FoodQuery.forms(of: "banana") == ["banana"])
    }

    @Test func everyJoinIsAnExplicitAnd() {
        // FTS5's implicit AND rejects a group beside a bare term, so the operator is
        // always spelled out. Verified against the real index, not assumed.
        #expect(
            FoodQuery.ftsMatchExpression(for: "oat flakes")
                == "\"oat\"* AND (\"flakes\"* OR \"flak\"* OR \"flake\"*)"
        )
    }

    @Test func aMixedQueryClausesEachTokenOnItsOwnTerms() {
        #expect(
            FoodQuery.ftsMatchExpression(for: "oats banana")
                == "(\"oats\"* OR \"oat\"*) AND \"banana\"*"
        )
    }

    @Test func caseDoesNotDecideWhetherSomethingIsAPlural() {
        #expect(FoodQuery.forms(of: "OATS") == ["OATS", "OAT"])
    }

    // MARK: - What a word is

    @Test func aWordIsLettersAndDigitsAndNothingElse() {
        #expect(FoodQuery.words(of: "Pizza, Margherita") == ["Pizza", "Margherita"])
        #expect(FoodQuery.words(of: "Milk, whole, 3.25% milkfat")
            == ["Milk", "whole", "3", "25", "milkfat"])
        #expect(FoodQuery.words(of: "  ") == [])
    }

    /// The fault this fixed. The term the prompt asks for carries commas, and they used to
    /// ride into the expression, where they defeated the plural forms: `"Oats,"` does not
    /// end in an "s" as far as `forms` can tell, so the singular that reaches "Oat flakes"
    /// was never searched.
    @Test func punctuationDoesNotChangeWhatIsSearchedFor() {
        #expect(
            FoodQuery.ftsMatchExpression(for: "Oats, rolled")
                == FoodQuery.ftsMatchExpression(for: "Oats rolled")
        )
        #expect(
            FoodQuery.ftsMatchExpression(for: "Pizza, Margherita")
                == "\"Pizza\"* AND \"Margherita\"*"
        )
    }

    @Test func bracketsAndPercentagesAreSeparatorsToo() {
        #expect(
            FoodQuery.ftsMatchExpression(for: "Pizza (cheese and tomato)")
                == "\"Pizza\"* AND \"cheese\"* AND \"and\"* AND \"tomato\"*"
        )
    }

    // MARK: - Preparation words

    @Test func preparationWordsAreRecognisedWhateverTheirCase() {
        #expect(FoodQuery.isPreparationWord("cooked"))
        #expect(FoodQuery.isPreparationWord("Raw"))
        #expect(FoodQuery.isPreparationWord("PREPACKED"))
    }

    @Test func aFoodIsNotAPreparationWord() {
        for food in ["pizza", "oats", "pasta", "rice", "chicken", "margherita"] {
            #expect(!FoodQuery.isPreparationWord(food))
        }
    }
}
