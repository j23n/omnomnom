import SwiftUI

/// One mark per day saying what kind of day it was.
///
/// Drawn once, under the first chart rather than at the bottom of the screen. With three
/// charts its position was nearly free; with eight, last would mean the reader meets
/// every line before learning how many days they are made of, and a confident reading of
/// a sparse month is the single conclusion this screen must not produce.
///
/// The ramp is one hue at three lightnesses plus an empty track — a sequential scale, so
/// the steps are told apart by lightness rather than by hue, which keeps it legible in
/// every kind of colour vision and in print. It is deliberately not a status palette:
/// nothing here is good or bad, and a day with nothing logged is a fact about the record
/// rather than a failure to be marked in red.
struct CoverageStrip: View {
    let points: [TrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(points) { point in
                        Rectangle()
                            .fill(Self.fill(point.state))
                            .frame(height: Self.height(point.state))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: proxy.size.width)
            }
            .frame(height: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.summary(points))

            legend
        }
    }

    private var legend: some View {
        // Four states, so identity is never carried by the ramp alone.
        FlowLayout(spacing: 10) {
            ForEach(DayState.allCases, id: \.self) { state in
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Self.fill(state))
                        .frame(width: 8, height: 8)
                    Text(Self.name(state))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One hue, light to dark, with an empty track at the bottom of the scale.
    static func fill(_ state: DayState) -> some ShapeStyle {
        switch state {
        case .complete: AnyShapeStyle(.primary)
        case .assumed: AnyShapeStyle(.primary.opacity(0.55))
        case .partial: AnyShapeStyle(.primary.opacity(0.3))
        case .empty: AnyShapeStyle(.quaternary)
        }
    }

    /// A shorter mark for a thinner day, so the strip reads without colour at all.
    static func height(_ state: DayState) -> CGFloat {
        switch state {
        case .complete: 18
        case .assumed: 13
        case .partial: 9
        case .empty: 3
        }
    }

    static func name(_ state: DayState) -> String {
        switch state {
        case .complete: "Complete"
        case .assumed: "Assumed"
        case .partial: "Partial"
        case .empty: "Nothing logged"
        }
    }

    /// What VoiceOver reads instead of ninety marks.
    static func summary(_ points: [TrendPoint]) -> String {
        var counts: [DayState: Int] = [:]
        for point in points { counts[point.state, default: 0] += 1 }
        let parts = DayState.allCases.compactMap { state -> String? in
            guard let count = counts[state], count > 0 else { return nil }
            return "\(count) \(name(state).lowercased())"
        }
        return "Coverage: " + TrendBasis.list(parts) + "."
    }
}

#if DEBUG
private func coveragePoints() -> [TrendPoint] {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let pattern: [DayState] = [.complete, .complete, .partial, .complete, .empty, .assumed, .complete]
    return (0..<30).map { index in
        TrendPoint(
            day: start.addingTimeInterval(Double(index) * 86_400),
            value: 2_000, mean: 2_000, state: pattern[index % pattern.count]
        )
    }
}

#Preview("A month", traits: .sizeThatFitsLayout) {
    CoverageStrip(points: coveragePoints())
        .padding()
}

#Preview("Dark", traits: .sizeThatFitsLayout) {
    CoverageStrip(points: coveragePoints())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
