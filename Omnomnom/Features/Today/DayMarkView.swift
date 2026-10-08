import DeveloperToolsSupport
import SwiftUI

/// The day as one mark: a ring around a square.
///
/// Two shapes for two jobs, so they can never be read as one. The **ring** is the record —
/// four segments, one per meal, drawn where that meal has an answer and left open where it
/// does not. The **square** is the composition — bands whose heights are each
/// macronutrient's share of the day's energy, with a hatched band for the part no figure
/// covers.
///
/// A square and not a disc, which is the one place in this design where the arithmetic beat
/// the shape it wanted: a band inside a circle is wider in the middle, so its area would
/// not match its number. A band in a square is exactly its share.
///
/// Scales from the 32 pt it is drawn at in a month grid to the 64 pt of a title row and the
/// 96 pt of a widget, because every measurement below is a fraction of `size` rather than a
/// number of points.
struct DayMarkView: View {
    /// Which meals have an answer of either kind.
    let answers: DayAnswers
    /// What the day was made of so far.
    let composition: MacroComposition
    /// A day accepted from the usual one rather than described. Drawn at half strength with
    /// a grey ring, so a day asserted never looks like a day accepted.
    var isAssumed: Bool = false
    /// The whole mark, point for point.
    var size: CGFloat = 64

    private var ringWidth: CGFloat { size * 0.078 }
    private var coreSide: CGFloat { size * 0.46 }
    private var coreRadius: CGFloat { size * 0.14 }
    /// How much of each quarter is given up to the gaps either side of it.
    private var segmentGap: CGFloat { 0.016 }

    var body: some View {
        ZStack {
            track
            segments
            core
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(answers: answers, composition: composition, isAssumed: isAssumed))
    }

    /// The open ring, which is what an unanswered meal looks like.
    private var track: some View {
        ForEach(MealSlot.allCases, id: \.self) { slot in
            arc(for: slot)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
        }
    }

    private var segments: some View {
        ForEach(MealSlot.allCases.filter { answers.isAnswered($0) }, id: \.self) { slot in
            arc(for: slot)
                .stroke(
                    isAssumed ? Color.secondary : Color.primary,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
        }
    }

    /// One quarter of the ring, with a gap either side, starting at the top.
    private func arc(for slot: MealSlot) -> some Shape {
        let index = MealSlot.allCases.firstIndex(of: slot) ?? 0
        let quarter = 1.0 / Double(MealSlot.allCases.count)
        let start = Double(index) * quarter + segmentGap
        let end = Double(index + 1) * quarter - segmentGap
        return Circle()
            .inset(by: ringWidth / 2)
            .trim(from: start, to: end)
            .rotation(.degrees(-90))
    }

    /// The bands, clipped to the rounded square.
    private var core: some View {
        VStack(spacing: 0) {
            ForEach(composition.bands) { band in
                BandFill(nutrient: band.nutrient, hatchSpacing: max(3, size * 0.06))
                    .frame(height: coreSide * band.share)
            }
            // An empty day still shows its square, as the shape of nothing yet.
            if composition.isEmpty {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: coreSide, height: coreSide)
        .opacity(isAssumed ? 0.45 : 1)
        .clipShape(RoundedRectangle(cornerRadius: coreRadius, style: .continuous))
    }

    /// "Three of four meals answered. Carbohydrate 51 per cent, fat 28, protein 19."
    ///
    /// Spoken as counts and shares, never as a fraction of the day: the ring names which
    /// meals are in rather than dividing them, for the reason in `DayState.note`.
    static func label(
        answers: DayAnswers, composition: MacroComposition, isAssumed: Bool
    ) -> String {
        var sentences: [String] = []
        let answered = answers.answered.count
        let total = MealSlot.allCases.count
        if answered == 0 {
            sentences.append("No meals answered yet.")
        } else if answers.isAnswered {
            sentences.append(isAssumed ? "All \(total) meals, from your usual day." : "All \(total) meals answered.")
        } else {
            sentences.append("\(answered) of \(total) meals answered.")
        }
        if !composition.isEmpty {
            let parts = composition.bands.map { band in
                let name = band.nutrient?.displayName ?? "not attributed"
                return "\(name) \(Int((band.share * 100).rounded())) per cent"
            }
            sentences.append(parts.joined(separator: ", ") + ".")
        }
        return sentences.joined(separator: " ")
    }
}

#if DEBUG
private let typicalDay = Nutrition(
    energy: 1320, protein: 63, carbohydrates: 168, fatTotal: 41, fiber: 32
)

#Preview("Every state", traits: .sizeThatFitsLayout) {
    let composition = MacroComposition(of: typicalDay)
    return HStack(alignment: .bottom, spacing: 18) {
        VStack {
            DayMarkView(answers: .empty, composition: .empty)
            Text("none").font(.caption2)
        }
        VStack {
            DayMarkView(answers: DayAnswers(logged: [.breakfast]), composition: composition)
            Text("one").font(.caption2)
        }
        VStack {
            DayMarkView(
                answers: DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]),
                composition: composition
            )
            Text("three").font(.caption2)
        }
        VStack {
            DayMarkView(
                answers: DayAnswers(logged: Set(MealSlot.allCases)), composition: composition
            )
            Text("answered").font(.caption2)
        }
        VStack {
            DayMarkView(
                answers: DayAnswers(logged: Set(MealSlot.allCases)),
                composition: composition,
                isAssumed: true
            )
            Text("your usual").font(.caption2)
        }
    }
    .padding()
}

#Preview("Sizes", traits: .sizeThatFitsLayout) {
    let composition = MacroComposition(of: typicalDay)
    let answers = DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack])
    return HStack(alignment: .bottom, spacing: 16) {
        DayMarkView(answers: answers, composition: composition, size: 32)
        DayMarkView(answers: answers, composition: composition, size: 64)
        DayMarkView(answers: answers, composition: composition, size: 96)
    }
    .padding()
}

#Preview("A missing figure", traits: .sizeThatFitsLayout) {
    // Apple juice has no fat figure in the bundled table, so the day's fat is a floor and
    // the part nothing accounts for is hatched rather than drawn as a nutrient.
    DayMarkView(
        answers: DayAnswers(logged: [.breakfast, .snack]),
        composition: MacroComposition(
            of: Nutrition(energy: 600, protein: 12, carbohydrates: 60, fatTotal: nil)
        ),
        size: 96
    )
    .padding()
}

#Preview("Dark", traits: .sizeThatFitsLayout) {
    // Deliberately unresolved: see NutrientPalette.
    DayMarkView(
        answers: DayAnswers(logged: [.breakfast, .lunch], skipped: [.snack]),
        composition: MacroComposition(of: typicalDay),
        size: 96
    )
    .padding()
    .preferredColorScheme(.dark)
}
#endif
