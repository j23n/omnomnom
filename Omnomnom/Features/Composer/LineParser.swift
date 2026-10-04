import Foundation

/// One food found in a typed line, before anything has been looked up.
///
/// `lookupTerm` is what the database search runs on and `name` is what the user sees.
/// The fallback parser puts the same text in both, because it has no idea what a
/// nutrition table would call something; the model tier is what fills them differently.
nonisolated struct ParsedItem: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The food as the line put it, with any quantity taken off the front.
    let name: String
    /// The same food in the wording a composition table uses.
    let lookupTerm: String
    /// A count the line gave: 2 for "2 eggs", 1 for "a banana", `nil` when it gave none.
    let count: Double?
    /// A size word the line gave: "large coffee". `nil` when it gave none.
    let size: AmountBucket?
    /// An explicit amount in the line's own unit: 200 for "200 g rice". Grams or
    /// millilitres as `measure` says. `nil` unless the line actually wrote one.
    let amount: Double?
    let measure: FoodMeasure

    init(
        id: UUID = UUID(), name: String, lookupTerm: String? = nil, count: Double? = nil,
        size: AmountBucket? = nil, amount: Double? = nil, measure: FoodMeasure = .mass
    ) {
        self.id = id
        self.name = name
        self.lookupTerm = lookupTerm ?? name
        self.count = count
        self.size = size
        self.amount = amount
        self.measure = measure
    }
}

/// Breaking a typed line into the foods in it, without a language model.
///
/// This exists so the primary way into the log works on every device. Apple
/// Intelligence is absent on iOS 26, on unsupported hardware, in unsupported regions
/// and whenever the user has turned it off, and "the main feature needs a setting you
/// do not have" is not an acceptable answer for the one path the app most wants people
/// to use.
///
/// It is deliberately dumb. It splits a list and takes a quantity off the front of each
/// part, which covers "oats, banana, coffee" and "2 eggs, 200g rice" — the overwhelming
/// common case, because someone typing a line in order to log it writes a list.
/// Everything cleverer is the model's job, and where the model exists it does it.
///
/// "with" never splits. "toast with butter" stays one fragment on purpose, so the
/// matcher can try a composite row before anything is broken into parts.
nonisolated enum LineParser {
    /// Longest line worth reading. The same bound the model prompt uses, so neither tier
    /// behaves differently from the other on a paragraph.
    static let maximumLength = 500

    /// What separates one food from the next: commas, newlines, semicolons, and the
    /// words a list is joined with. Never "with".
    static let separators = [",", ";", "\n", "\r", " and ", " & ", " + ", " plus ", " und ", " et "]

    /// Words that name a container or a measure rather than a food, dropped once a count
    /// has been read off the front: "2 slices of bread" is bread.
    static let containers: Set<String> = [
        "slice", "slices", "piece", "pieces", "cup", "cups", "bowl", "bowls", "glass",
        "glasses", "plate", "plates", "portion", "portions", "serving", "servings",
        "handful", "handfuls", "spoon", "spoons", "tbsp", "tsp", "tablespoon",
        "tablespoons", "teaspoon", "teaspoons", "can", "cans", "bottle", "bottles",
        "scheibe", "scheiben", "stuck", "tasse", "tassen", "glas", "teller",
        "tranche", "tranches", "verre", "verres", "assiette", "bol",
    ]

    /// Units an explicit amount can be written in, and what each one means.
    static let units: [String: (factor: Double, measure: FoodMeasure)] = [
        "g": (1, .mass), "gram": (1, .mass), "grams": (1, .mass), "gramm": (1, .mass),
        "kg": (1000, .mass), "kilo": (1000, .mass), "kilos": (1000, .mass),
        "ml": (1, .volume), "millilitre": (1, .volume), "millilitres": (1, .volume),
        "l": (1000, .volume), "litre": (1000, .volume), "litres": (1000, .volume),
        "liter": (1000, .volume), "cl": (10, .volume), "dl": (100, .volume),
    ]

    /// The foods in a line, in the order they were written. Empty when there are none.
    ///
    /// A fragment that turns out to be only a size is given to the food before it. People
    /// write "chicken curry with rice, big portion" and mean the curry was big; dropping
    /// that silently would lose the one thing they said about the amount.
    static func parse(_ line: String) -> [ParsedItem] {
        var items: [ParsedItem] = []
        for fragment in fragments(of: String(line.prefix(maximumLength))) {
            switch read(fragment) {
            case .food(let item):
                items.append(item)
            case .size(let bucket):
                guard let last = items.last, last.size == nil else { continue }
                items[items.count - 1] = ParsedItem(
                    id: last.id, name: last.name, lookupTerm: last.lookupTerm, count: last.count,
                    size: bucket, amount: last.amount, measure: last.measure
                )
            case .nothing:
                continue
            }
        }
        return items
    }

    /// The line split into one part per food, blank parts dropped.
    static func fragments(of line: String) -> [String] {
        var parts = [line]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Articles that mean one of something: "a banana" is one banana.
    static let articles: Set<String> = ["a", "an", "ein", "eine", "einen", "un", "une"]

    /// Words that join a container to its food and carry nothing once the container has
    /// gone: "2 slices of bread" must not read back as "of bread".
    static let connectors: Set<String> = ["of", "von", "de", "du", "da", "with", "mit", "avec"]

    /// A number glued to its unit, as people actually type it: "200g" is 200 grams.
    /// `nil` unless the token really is digits followed by letters.
    static func gluedAmount(_ token: String) -> (number: Double, unit: String)? {
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let number = Double(digits) else { return nil }
        let unit = String(token.dropFirst(digits.count))
        guard !unit.isEmpty, unit.allSatisfy(\.isLetter) else { return nil }
        return (number, unit)
    }

    /// What one fragment turned out to hold.
    nonisolated enum Fragment: Hashable, Sendable {
        case food(ParsedItem)
        /// A size and nothing else: the "big portion" of "chicken curry with rice, big
        /// portion", which belongs to the food before it rather than to nothing.
        case size(AmountBucket)
        case nothing
    }

    /// One fragment read into an item, or `nil` when nothing but a quantity is left.
    ///
    /// "2" on its own is not a food, and neither is "a large". A fragment that reduces
    /// to nothing is dropped rather than carried as an empty row for the user to delete.
    ///
    /// The name keeps the words as they were written and the lookup term does not. That
    /// is what the two fields are for: "toast with butter" has to read that way on screen,
    /// while the search wants "toast butter", because the index ands its tokens together
    /// and a row called "Bread, buttered" holds no "with" to match.
    static func item(from fragment: String) -> ParsedItem? {
        guard case .food(let item) = read(fragment) else { return nil }
        return item
    }

    /// The same reading, keeping a size-only fragment rather than discarding it.
    static func read(_ fragment: String) -> Fragment {
        var words = fragment
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !words.isEmpty else { return .nothing }

        /// The comparable form of a word: folded, stripped of the punctuation a typed
        /// list leaves behind.
        func key(_ word: String) -> String { PhraseKey.fold(word) }

        var count: Double?
        var size: AmountBucket?
        var amount: Double?
        var measure = FoodMeasure.mass

        // A leading number is an explicit amount when a unit follows it and a count when
        // one does not: "0.5 l milk" is half a litre, "2 eggs" is two eggs. A leading
        // article counts as one.
        if let first = words.first.map(key) {
            if let glued = gluedAmount(first), let unit = units[glued.unit] {
                words.removeFirst()
                amount = glued.number * unit.factor
                measure = unit.measure
            } else if let number = Double(first) ?? PhraseKey.numberWords[first].flatMap(Double.init) {
                words.removeFirst()
                if let unitWord = words.first.map(key), let unit = units[unitWord] {
                    words.removeFirst()
                    amount = number * unit.factor
                    measure = unit.measure
                } else {
                    count = number
                }
            } else if articles.contains(first) {
                words.removeFirst()
                count = 1
            }
        }

        // A size word anywhere in what is left, taken out of the name once found.
        if let index = words.firstIndex(where: { AmountBucket.named(key($0)) != nil }) {
            size = AmountBucket.named(key(words[index]))
            words.remove(at: index)
        }

        // Container words, now that any count has been read off, and then the connector
        // they leave stranded.
        words.removeAll { containers.contains(key($0)) }
        while let first = words.first.map(key), connectors.contains(first) {
            words.removeFirst()
        }

        let name = words.joined(separator: " ").trimmingCharacters(
            in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;:!?"))
        )
        let lookupTerm = PhraseKey.tokens(name).joined(separator: " ")
        guard !name.isEmpty, !lookupTerm.isEmpty else {
            return size.map(Fragment.size) ?? .nothing
        }
        return .food(
            ParsedItem(
                name: name,
                lookupTerm: lookupTerm,
                count: count,
                size: size,
                amount: amount,
                measure: measure
            )
        )
    }
}
