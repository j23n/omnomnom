import Foundation

/// One row of a day, reduced to what a loose end has to know about it.
nonisolated struct LoggedRow: Hashable, Sendable {
    let entryID: UUID
    let foodName: String
    /// What the line called this food, when a line is what logged it.
    let wording: String?
    /// Whether the app chose the food rather than the user.
    let guessed: Bool
    /// Nutrients this row's frozen snapshot holds no figure for, which is what makes the
    /// day's total for them a floor.
    let missing: Set<Nutrient>

    init(
        entryID: UUID, foodName: String, wording: String? = nil, guessed: Bool = false,
        missing: Set<Nutrient> = []
    ) {
        self.entryID = entryID
        self.foodName = foodName
        self.wording = wording
        self.guessed = guessed
        self.missing = missing
    }
}

/// Everything left to answer about one day, as a queue of cards.
///
/// The screen it drives exists only when something is incomplete, and what it must never
/// become is a chore list. Three rules hold it to that:
///
/// - **Nothing here is a percentage and nothing fills a bar.** A count goes down and the
///   mark's ring closes. There is no progress to be at 60 per cent of.
/// - **Every card's second answer costs nothing.** "Nothing tonight" is a real answer and
///   it is what closes a meal without inventing food; "it is right" closes a question
///   about a match without changing anything. A queue where every exit writes something is
///   a queue that teaches people to invent food.
/// - **A day the cadence does not ask about raises nothing.** The cadence decides when the
///   app speaks, and this is the app speaking.
///
/// Derived, never stored, from what the day already holds.
nonisolated struct LooseEnd: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A meal with no answer of either kind.
        case unansweredMeal(MealSlot)
        /// A row whose food the app chose rather than the user.
        case guessedMatch
        /// A nutrient the day's total is a floor for, because some row has no figure.
        case missingFigure(Nutrient)
        /// Every meal is answered and the day itself has not been closed.
        case dayNotClosed
    }

    let kind: Kind
    /// The entry this is about, when it is about one.
    let entryID: UUID?
    /// The card's first line.
    let title: String
    /// The sentence under it, which is what the person needs in order to answer.
    let detail: String

    var id: String {
        switch kind {
        case .unansweredMeal(let slot): "meal-\(slot.rawValue)"
        case .guessedMatch: "guess-\(entryID?.uuidString ?? "")"
        case .missingFigure(let nutrient): "missing-\(nutrient.rawValue)"
        case .dayNotClosed: "day"
        }
    }

    /// The whole queue, in the order it is worked.
    ///
    /// Unanswered meals first, because they are the only cards that change what the day
    /// says it holds. Then the matches the app guessed, then the figures it has no value
    /// for — both of which are about rows that are already logged. The day itself is last:
    /// it is what clearing the rest leads to, and it only appears once there is nothing
    /// else owed.
    static func items(
        rows: [LoggedRow],
        answers: DayAnswers,
        usual: [MealSlot: String] = [:],
        isAsked: Bool,
        isClosed: Bool
    ) -> [LooseEnd] {
        guard isAsked else { return [] }
        var items: [LooseEnd] = []

        for slot in answers.unanswered {
            items.append(LooseEnd(
                kind: .unansweredMeal(slot),
                entryID: nil,
                title: "\(slot.displayName) is unanswered",
                detail: usual[slot].map { "You usually have \($0)." }
                    ?? "Say what you had, or say there was nothing."
            ))
        }

        for row in rows where row.guessed {
            items.append(LooseEnd(
                kind: .guessedMatch,
                entryID: row.entryID,
                title: row.foodName,
                detail: row.wording.flatMap { $0.isEmpty ? nil : "From “\($0)”" } ?? "Matched for you"
            ))
        }

        // By nutrient rather than by row. Two thirds of the bundled table is complete and
        // the rest is short of something, so a card per row would bury everything else
        // here on an ordinary day; a card per figure is at most eight and is also the
        // honest unit, since what is a floor is the day's total and not the row.
        for nutrient in Nutrient.allCases {
            let short = rows.filter { $0.missing.contains(nutrient) }
            guard !short.isEmpty else { continue }
            let names = short.map(\.foodName).formatted(.list(type: .and))
            items.append(LooseEnd(
                kind: .missingFigure(nutrient),
                entryID: short.count == 1 ? short[0].entryID : nil,
                title: short.count == 1
                    ? "One food has no \(nutrient.displayName.lowercased()) figure"
                    : "\(short.count) foods have no \(nutrient.displayName.lowercased()) figure",
                detail: "\(names). Today's \(nutrient.displayName.lowercased()) is a floor, not a total."
            ))
        }

        if answers.isAnswered, !isClosed {
            items.append(LooseEnd(
                kind: .dayNotClosed,
                entryID: nil,
                title: "The day is not closed",
                detail: "Closing it says that is everything you ate. Closed days are what the run counts."
            ))
        }
        return items
    }

    /// "3 loose ends", or what there is to say when there are none.
    static func heading(_ count: Int) -> String {
        switch count {
        case 0: "Nothing loose"
        case 1: "1 loose end"
        default: "\(count) loose ends"
        }
    }

    /// The line under the heading: what clearing the queue gets you, named as the day.
    ///
    /// It promises the day will be answered, which is true only because `dayNotClosed` is
    /// in the queue whenever it is not. Without that card this sentence would be a lie on
    /// exactly the days someone is most likely to read it.
    static func subheading(_ count: Int, day: String) -> String {
        count == 0 ? "\(day) is answered" : "Clear these and \(day) is answered"
    }
}

/// The queue for a day, from the rows and records a screen already has in hand.
///
/// Separate from `items(rows:answers:usual:isAsked:isClosed:)`, which knows nothing about
/// the store and is where the rules are. This is only the reading: the two screens that
/// show the queue — the row on Today that counts it and the queue itself — must agree, and
/// the only way to guarantee that is for them to call the same thing.
@MainActor
extension LooseEnd {
    static func items(
        entries: [LogEntry],
        record: DayRecord?,
        baselines: [BaselinePhrase],
        day: Date,
        cadence: SamplingCadence,
        calendar: Calendar = .current
    ) -> [LooseEnd] {
        var usual: [MealSlot: String] = [:]
        for baseline in baselines where baseline.isOfferable {
            if let phrase = baseline.phrase {
                usual[baseline.mealSlot] = phrase.text
            }
        }
        return items(
            rows: entries.map { entry in
                LoggedRow(
                    entryID: entry.id,
                    foodName: entry.foodName,
                    wording: entry.wording,
                    guessed: entry.guessed,
                    missing: entry.snapshot.missingNutrients
                )
            },
            answers: DayAnswers(
                entrySlots: entries.map(\.mealSlot),
                skipped: record?.skippedSlots ?? []
            ),
            usual: usual,
            isAsked: cadence.asks(about: day, calendar: calendar),
            isClosed: record?.isComplete ?? false
        )
    }
}
