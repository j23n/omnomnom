import SwiftUI

/// The colours a chart uses to tell one macronutrient from another.
///
/// Its own namespace, and the one place in the app where a hue carries meaning. Everywhere
/// else the tint means "you can act on this" and nothing is coloured that is not a control;
/// inside a chart mark or its legend swatch, a hue is a nutrient's identity. A figure in a
/// table is still never tinted, which is what keeps the two readings apart.
///
/// Nothing here encodes good or bad. There is no good macronutrient.
///
/// The three were chosen by measuring rather than by eye, because the obvious sets fail.
/// A warm triad put tangerine against gold at a colour-vision separation of 1.3, and blue
/// against violet at 1.7 — indistinguishable. Green was ruled out for reading as a verdict
/// whatever the legend says. Worst separation in the set below is 11.1 under protanopia
/// and 18.8 under normal vision, and all three clear 3:1 against white and against the
/// grouped-list background.
///
/// Dark mode is deliberately absent.
///
/// Measured, not overlooked: the dark lightness band is narrow enough that tangerine
/// and the fat hue cannot be got 15 apart under normal vision inside it, and a
/// separation that small is not something a legend or a direct label can rescue. The
/// honest options are a different third hue or two hues and a neutral, and both are
/// decisions for the dark-mode pass rather than guesses to make here. Until then these
/// values are used in both appearances and are too heavy in the dark one.
nonisolated enum NutrientPalette {
    /// Protein.
    static let protein = Color(red: 0.180, green: 0.373, blue: 0.639)
    /// Carbohydrate. The brand tangerine, which is the one hue shared with the chrome.
    static let carbohydrates = Color(red: 0.910, green: 0.392, blue: 0.110)
    /// Fat.
    static let fat = Color(red: 0.690, green: 0.188, blue: 0.376)

    /// The ink a hatch is drawn in, for the part of a figure no row has a value for.
    ///
    /// A pattern and not a colour, so that "no figure" never competes with a nutrient's
    /// identity and survives being printed, photocopied or read by someone who sees no
    /// colour at all.
    static let missing = Color(red: 0.463, green: 0.463, blue: 0.463)

    /// The colour for one macronutrient, or `missing` for anything that is not one.
    static func color(for nutrient: Nutrient?) -> Color {
        switch nutrient {
        case .protein: protein
        case .carbohydrates: carbohydrates
        case .fatTotal: fat
        default: missing
        }
    }
}

/// Diagonal hatching, for the part of a figure that no row has a value for.
///
/// The only pattern in the app, used wherever a missing figure appears: on a bar, in the
/// day mark's core, and beside a nutrient total. One shape so the angle and the spacing
/// cannot drift apart between them.
nonisolated struct Hatch: Shape {
    /// Distance between lines, in points.
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0, rect.width > 0, rect.height > 0 else { return path }
        // Starting a height to the left and running a height past the right edge is what
        // makes every line reach both sides at 45 degrees.
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// One band of a composition, filled: a nutrient's colour, or the hatch for what no row
/// has a figure for.
///
/// Shared by the day mark and the composition bar so the two can never disagree about
/// what a missing figure looks like.
struct BandFill: View {
    let nutrient: Nutrient?
    var hatchSpacing: CGFloat = 5

    var body: some View {
        if nutrient == nil {
            ZStack {
                Rectangle().fill(.background)
                Hatch(spacing: hatchSpacing)
                    .stroke(NutrientPalette.missing, lineWidth: 1.2)
            }
        } else {
            NutrientPalette.color(for: nutrient)
        }
    }
}

#if DEBUG
#Preview("The three, and the hatch", traits: .sizeThatFitsLayout) {
    HStack(spacing: 12) {
        ForEach([Nutrient.protein, .carbohydrates, .fatTotal], id: \.self) { nutrient in
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(NutrientPalette.color(for: nutrient))
                    .frame(width: 56, height: 56)
                Text(nutrient.shortName).font(.caption)
            }
        }
        VStack(spacing: 6) {
            Hatch()
                .stroke(NutrientPalette.missing, lineWidth: 1.5)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 56, height: 56)
            Text("No figure").font(.caption)
        }
    }
    .padding()
}
#endif
