import DeveloperToolsSupport
import Foundation
import SwiftUI

/// What a day, a meal or one food was made of, as a bar of shares.
///
/// A bar and not a ring, because the question is proportion and proportions have to be
/// comparable across days: seven bars stacked up read as drift, seven rings read as
/// nothing. The ring in `DayMarkView` keeps the job it is best at, which is how much of
/// something is done.
///
/// Optional ticks above it mark the same shares over a longer window — your own usual
/// month. A comparison to yourself and never to a target: nothing here says a share is
/// high or low, only that today is not where the month sits.
struct CompositionBar: View {
    let composition: MacroComposition
    /// The same figures over a longer window, drawn as ticks. `nil` hides them, which is
    /// right until there is a month to compare against.
    var usual: MacroComposition?
    var height: CGFloat = 24

    private var corner: CGFloat { height / 2 }
    /// The surface showing between bands, so neighbouring colours never touch.
    private var gap: CGFloat { 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usual, !usual.isEmpty {
                ticks(for: usual)
            }
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(composition))
    }

    private var bar: some View {
        GeometryReader { proxy in
            let bands = composition.bands
            let available = max(0, proxy.size.width - gap * CGFloat(max(0, bands.count - 1)))
            HStack(spacing: gap) {
                ForEach(bands) { band in
                    BandFill(nutrient: band.nutrient)
                        .frame(width: available * band.share)
                }
                if bands.isEmpty {
                    Rectangle().fill(.quaternary)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    /// One mark at each boundary between the usual shares, so today's bands can be read
    /// against them without a second bar competing for the eye.
    private func ticks(for usual: MacroComposition) -> some View {
        GeometryReader { proxy in
            ForEach(Array(Self.boundaries(of: usual).enumerated()), id: \.offset) { pair in
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 1.5, height: 8)
                    .offset(x: proxy.size.width * pair.element)
            }
        }
        .frame(height: 8)
    }

    /// The cumulative shares at which one band gives way to the next, excluding the ends.
    static func boundaries(of composition: MacroComposition) -> [Double] {
        var running = 0.0
        var boundaries: [Double] = []
        for band in composition.bands {
            running += band.share
            boundaries.append(running)
        }
        // The last boundary is the right-hand edge, which is not a mark.
        return boundaries.dropLast().map { min(max($0, 0), 1) }
    }

    /// "Carbohydrate 51 per cent, fat 28 per cent, protein 19 per cent, not attributed 2."
    static func label(_ composition: MacroComposition) -> String {
        guard !composition.isEmpty else { return "Nothing logged yet." }
        let parts = composition.bands
            .sorted { $0.share > $1.share }
            .map { band in
                let name = band.nutrient?.displayName ?? "not attributed"
                return "\(name) \(Int((band.share * 100).rounded())) per cent"
            }
        return parts.joined(separator: ", ") + "."
    }
}

/// The bar's legend: a swatch, a name, the grams and the share.
///
/// Always present, because identity must never rest on colour alone, and the figures stay
/// in the text colours — a swatch beside them carries the identity instead.
struct CompositionLegend: View {
    let composition: MacroComposition
    /// The amounts the shares were taken from, for the gram figures.
    let nutrition: Nutrition
    /// Whether to show those gram figures. Off where the totals are already on the screen
    /// underneath, which is Today: the same number twice reads as two different numbers.
    var showsGrams: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(composition.bands) { band in
                HStack(spacing: 8) {
                    BandFill(nutrient: band.nutrient, hatchSpacing: 3)
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(band.nutrient?.displayName ?? "No figure covers it")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsGrams, let nutrient = band.nutrient, let grams = nutrition[nutrient] {
                        ValueText(grams, unit: nutrient.unit)
                            .fontWeight(.semibold)
                    }
                    Text(Self.share(band.share))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if !composition.missing.isEmpty {
                Text(Self.missingNote(composition.missing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func share(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    /// "Some of this has no figure for fat, so that total is a floor."
    ///
    /// Said in words rather than left to the hatch alone, because a total built on a row
    /// with a gap in it is a different claim from a total, and the difference is not a
    /// detail. Named in the nutrients' own display order, never in order of how much is
    /// missing, which would be a judgement about which gap matters.
    static func missingNote(_ missing: Set<Nutrient>) -> String {
        let names = Nutrient.allCases
            .filter { missing.contains($0) }
            .map { $0.displayName.lowercased() }
        let list = names.formatted(.list(type: .and))
        let totals = names.count == 1 ? "that total is" : "those totals are"
        return "Some of this has no figure for \(list), so \(totals) a floor."
    }
}

#if DEBUG
private let typicalDay = Nutrition(
    energy: 1320, protein: 63, carbohydrates: 168, fatTotal: 41, fiber: 32
)
private let usualMonth = Nutrition(
    energy: 2120, protein: 88, carbohydrates: 241, fatTotal: 76, fiber: 29
)

#Preview("A day, against the usual month", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 14) {
        CompositionBar(
            composition: MacroComposition(of: typicalDay),
            usual: MacroComposition(of: usualMonth)
        )
        CompositionLegend(composition: MacroComposition(of: typicalDay), nutrition: typicalDay)
    }
    .padding()
}

#Preview("No month to compare with yet", traits: .sizeThatFitsLayout) {
    CompositionBar(composition: MacroComposition(of: typicalDay))
        .padding()
}

#Preview("A missing figure", traits: .sizeThatFitsLayout) {
    let day = Nutrition(energy: 600, protein: 12, carbohydrates: 60, fatTotal: nil)
    return VStack(alignment: .leading, spacing: 14) {
        CompositionBar(composition: MacroComposition(of: day))
        CompositionLegend(composition: MacroComposition(of: day), nutrition: day)
    }
    .padding()
}

#Preview("Nothing logged", traits: .sizeThatFitsLayout) {
    CompositionBar(composition: .empty).padding()
}

#Preview("One food", traits: .sizeThatFitsLayout) {
    // Butter, which is almost all fat: the order of the bands does not follow their size.
    let butter = Nutrition(energy: 732, protein: 1.2, carbohydrates: 0.6, fatTotal: 80.6)
    return CompositionBar(composition: MacroComposition(of: butter), height: 12)
        .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 14) {
        CompositionBar(composition: MacroComposition(of: typicalDay))
        CompositionLegend(composition: MacroComposition(of: typicalDay), nutrition: typicalDay)
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
