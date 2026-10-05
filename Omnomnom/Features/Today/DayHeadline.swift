import DeveloperToolsSupport
import SwiftUI

/// The day as one mark and one sentence, above everything else on Today.
///
/// The first thing on the screen is what the day *is*, not what it adds up to. The mark
/// carries both halves of that — which meals have an answer, in the ring, and what the day
/// was made of, in the square — and the sentence beside it says the first half in words,
/// since a ring read at a glance is a shape and not a number.
///
/// It names meals and never divides them. "3 of 4 meals" is a fact; "75 per cent of your
/// day" is a claim about how much a day should hold, which is not this app's to make. The
/// reasoning is in `DayState.note` and it governs every count on this screen.
///
/// The figures stay below, in the totals: this is the headline and a headline carrying two
/// energy figures is two headlines.
struct DayHeadline: View {
    let answers: DayAnswers
    let composition: MacroComposition
    /// A day accepted from the usual one rather than described.
    var isAssumed: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            DayMarkView(answers: answers, composition: composition, isAssumed: isAssumed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(answers.sentence)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(Self.note(answers: answers, isAssumed: isAssumed))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One element, and the mark is hidden above rather than spoken twice: the mark's
        // own label says the count and then the composition, which is exactly what is
        // wanted here and in that order.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            DayMarkView.label(answers: answers, composition: composition, isAssumed: isAssumed)
        )
    }

    /// The line under the count: what is still owed, or where the day came from.
    ///
    /// It names the meals rather than counting them, because "breakfast and lunch" is
    /// something a person can act on and "2 unanswered" is only a score. A day with every
    /// meal answered says so in the plainest words available.
    static func note(answers: DayAnswers, isAssumed: Bool) -> String {
        if isAssumed { return "Taken from your usual day" }
        let owed = answers.unanswered
        guard !owed.isEmpty else { return "Nothing left to answer" }
        let names = owed.map { $0.displayName.lowercased() }
        return "Still to answer: \(names.formatted(.list(type: .and)))"
    }
}

#if DEBUG
private let typicalDay = Nutrition(
    energy: 1320, protein: 63, carbohydrates: 168, fatTotal: 41, fiber: 32
)

#Preview("Three of four", traits: .sizeThatFitsLayout) {
    DayHeadline(
        answers: DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]),
        composition: MacroComposition(of: typicalDay)
    )
    .padding()
}

#Preview("Nothing yet", traits: .sizeThatFitsLayout) {
    DayHeadline(answers: .empty, composition: .empty)
        .padding()
}

#Preview("All four", traits: .sizeThatFitsLayout) {
    DayHeadline(
        answers: DayAnswers(logged: Set(MealSlot.allCases)),
        composition: MacroComposition(of: typicalDay)
    )
    .padding()
}

#Preview("Taken from the usual day", traits: .sizeThatFitsLayout) {
    DayHeadline(
        answers: DayAnswers(logged: Set(MealSlot.allCases)),
        composition: MacroComposition(of: typicalDay),
        isAssumed: true
    )
    .padding()
}

#Preview("A missing figure", traits: .sizeThatFitsLayout) {
    DayHeadline(
        answers: DayAnswers(logged: [.breakfast, .snack]),
        composition: MacroComposition(
            of: Nutrition(energy: 600, protein: 12, carbohydrates: 60, fatTotal: nil)
        )
    )
    .padding()
}

#Preview("With the bar under it, as Today has it", traits: .sizeThatFitsLayout) {
    let composition = MacroComposition(of: typicalDay)
    return VStack(alignment: .leading, spacing: 16) {
        DayHeadline(
            answers: DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]),
            composition: composition
        )
        CompositionBar(composition: composition)
        CompositionLegend(composition: composition, nutrition: typicalDay, showsGrams: false)
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    DayHeadline(
        answers: DayAnswers(logged: [.breakfast]),
        composition: MacroComposition(of: typicalDay)
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
