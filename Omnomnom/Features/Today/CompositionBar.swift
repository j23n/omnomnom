import DeveloperToolsSupport
import Foundation
import SwiftUI

/// What a day, a meal or one food was made of, as a bar of shares.
///
/// A bar and not a ring, because the question is proportion and proportions have to be
/// comparable across days: seven bars stacked up read as drift, seven rings read as
/// nothing. The ring in `DayMarkView` keeps the job it is best at, which is how much of
/// something is done.
struct CompositionBar: View {
    let composition: MacroComposition

    /// The surface showing between bands, so neighbouring colours never touch.
    private var gap: CGFloat { 2 }

    var body: some View {
        GeometryReader { proxy in
            let bands = composition.bands
            let available = max(0, proxy.size.width - gap * CGFloat(max(0, bands.count - 1)))
            HStack(spacing: gap) {
                ForEach(bands) { band in
                    BandFill(nutrient: band.nutrient)
                        .frame(width: available * band.share)
                }
            }
        }
        .frame(height: 24)
        // Half the height, which rounds the ends off completely.
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(composition))
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

/// The bar's legend: a swatch, a name and the share.
///
/// Always present, because identity must never rest on colour alone, and the figures stay
/// in the text colours — a swatch beside them carries the identity instead.
///
/// Shares and no gram figures: the one screen with a legend on it has the totals directly
/// underneath, and the same number twice on one screen reads as two different numbers.
struct CompositionLegend: View {
    let composition: MacroComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(composition.bands) { band in
                HStack(spacing: 8) {
                    BandFill(nutrient: band.nutrient, hatchSpacing: 3)
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(band.nutrient?.displayName ?? "No figure covers it")
                        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("A typical day", traits: .sizeThatFitsLayout) {
    CompositionBar(composition: MacroComposition(of: typicalDay))
        .padding()
}

#Preview("A missing figure", traits: .sizeThatFitsLayout) {
    let day = Nutrition(energy: 600, protein: 12, carbohydrates: 60, fatTotal: nil)
    return VStack(alignment: .leading, spacing: 14) {
        CompositionBar(composition: MacroComposition(of: day))
        CompositionLegend(composition: MacroComposition(of: day))
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 14) {
        CompositionBar(composition: MacroComposition(of: typicalDay))
        CompositionLegend(composition: MacroComposition(of: typicalDay))
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
