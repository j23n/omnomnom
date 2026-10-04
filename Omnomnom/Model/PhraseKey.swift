import Foundation

/// Turning a typed line into the key its memory is filed under.
///
/// This is the whole trick of phrase recall, so it is one function and it is tested.
/// "oats with a banana" and "Banana and oats!" have to reach the same record, because
/// nobody retypes a line the way they typed it last week, and a memory that only
/// answers an exact repetition would answer almost never.
///
/// Sorting the tokens is what buys that. It also means word order carries no meaning
/// here, so "chicken with rice" and "rice with chicken" are one phrase — correct, since
/// they are one meal — at the price that two genuinely different meals could collapse
/// into one key. That is survivable because a recalled phrase is shown and can be
/// corrected, and correcting it rewrites the record.
///
/// Quantities are kept rather than stripped. "2 eggs" and "3 eggs" are different
/// phrases holding different amounts, which is the point; what is normalised is only
/// how a quantity is written, so "two eggs" and "2 eggs" are the same one.
nonisolated enum PhraseKey {
    /// Words that carry no food in them. Dropped so that writing a line more or less
    /// politely does not file it somewhere else.
    static let fillers: Set<String> = [
        // English
        "a", "an", "the", "and", "with", "of", "some", "my", "plus", "then", "also",
        "for", "to", "in", "on", "bit", "little", "had", "ate", "eaten", "i",
        // German
        "ein", "eine", "einen", "der", "die", "das", "und", "mit", "etwas", "mein",
        "meine", "von", "zum", "zur", "habe", "gegessen",
        // French
        "un", "une", "le", "la", "les", "des", "du", "de", "et", "avec", "mon", "ma",
        "peu", "mange",
    ]

    /// Number words to digits, so how a count is spelled never splits a phrase.
    static let numberWords: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
        "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12",
        "half": "0.5",
        "eins": "1", "zwei": "2", "drei": "3", "vier": "4", "funf": "5", "sechs": "6",
        "sieben": "7", "acht": "8", "neun": "9", "zehn": "10", "halb": "0.5",
        "deux": "2", "trois": "3", "quatre": "4", "cinq": "5", "six_fr": "6", "sept": "7",
        "huit": "8", "neuf": "9", "dix": "10", "demi": "0.5",
    ]

    /// The key a line is filed under, or `nil` when nothing is left to file it by.
    ///
    /// A line of nothing but filler words — "and some of my" — has no key, which is
    /// correct: there is no food in it to remember.
    static func normalise(_ text: String) -> String? {
        let kept = tokens(text)
        guard !kept.isEmpty else { return nil }
        return kept.sorted().joined(separator: " ")
    }

    /// The tokens a key is built from, in the order they were typed, filler dropped and
    /// numbers written as digits. Exposed because the parser splits on the same notion
    /// of a word, and two notions of a word would drift apart.
    static func tokens(_ text: String) -> [String] {
        fold(text)
            .split(separator: " ")
            .map { numberWords[String($0)] ?? String($0) }
            .filter { !fillers.contains($0) && !$0.isEmpty }
    }

    /// Case folded, diacritics removed, everything that is not a letter or a digit
    /// turned into a space.
    ///
    /// Punctuation goes, unlike in `SearchRelevance.fold`, which keeps it because it is
    /// scoring against database names that contain it. Here the text is what a person
    /// typed, and "oats, banana" and "oats banana" are the same intention.
    static func fold(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil
        )
        let spaced = folded.map { character -> Character in
            character.isLetter || character.isNumber || character == "." ? character : " "
        }
        return String(spaced)
            .split(whereSeparator: \.isWhitespace)
            .map { trimStray($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Drops a full stop that is punctuation rather than a decimal point, so "oats."
    /// files with "oats" while "0.5" keeps its point.
    private static func trimStray(_ token: Substring) -> String {
        var text = String(token)
        while let last = text.last, last == ".", !(text.dropLast().last?.isNumber ?? false) {
            text.removeLast()
        }
        while let first = text.first, first == "." {
            text.removeFirst()
        }
        return text
    }
}
