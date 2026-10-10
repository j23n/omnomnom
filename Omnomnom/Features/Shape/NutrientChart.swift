import Charts
import SwiftUI

/// One measure over time: the daily figures, and the seven-day mean through them.
///
/// One measure, one axis, one chart. Eight nutrients on different scales means eight
/// charts and never two scales on one — a second y-axis is the most reliable way to make
/// a chart say something untrue.
///
/// No legend, because there is one series and the title names it. No colour carrying any
/// meaning: the mean is the primary ink and the daily points are recessive, so what the
/// eye follows is the line and the points are context. Nothing is tinted, because in this
/// app the tint means "you can act on this", and a figure is not actionable.
///
/// Deliberately absent: a reference line, a shaded band, an arrow, a comparison with
/// anything. A chart of what someone ate describes. The same chart with a band behind it
/// judges, and judging is both the wrong product and the edge of a regulatory boundary
/// this app stays well clear of.
struct NutrientChart: View {
    let trend: NutrientTrend
    /// The day the crosshair is on, shared across every chart so one gesture reads them
    /// all at the same date.
    @Binding var selected: Date?

    private var unit: NutrientUnit { trend.nutrient.unit }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if trend.hasData {
                chart
            } else {
                Text("Nothing logged for this in this range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 60, alignment: .center)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(trend.nutrient.displayName)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .privacySensitive()
        }
    }

    /// Says what the chart measures, which is a fact about the data and belongs on screen
    /// permanently. It never says how much to trust the line: that is an interpretation
    /// of the user's own figures, and an app that annotates which of someone's numbers to
    /// believe is a step from telling them what to do about it.
    private var subtitle: String {
        var text = "7-day mean, \(unit.symbol)"
        if let caveat = trend.nutrient.measurementCaveat {
            text += " · \(caveat)"
        }
        if let mean = trend.completeDayMean {
            text += " · \(Formatters.amount(mean, unit: unit)) on a complete day"
        }
        return text
    }

    private var chart: some View {
        Chart {
            ForEach(trend.points) { point in
                if let value = point.value {
                    PointMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value(trend.nutrient.displayName, value)
                    )
                    .symbolSize(8)
                    .foregroundStyle(.secondary.opacity(0.45))
                }
            }
            ForEach(Array(TrendMath.segments(trend.points).enumerated()), id: \.offset) { run in
                ForEach(run.element) { point in
                    if let mean = point.mean {
                        LineMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value(trend.nutrient.displayName, mean),
                            series: .value("Run", run.offset)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(.primary)
                        .interpolationMethod(.monotone)
                    }
                }
            }
            if let selected, let point = trend.points.first(where: { $0.day == selected }) {
                RuleMark(x: .value("Day", point.day, unit: .day))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        CrosshairLabel(point: point, unit: unit)
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 96)
        .privacySensitive()
        .accessibilityLabel(trend.nutrient.displayName)
        .accessibilityValue(Self.accessibilitySummary(trend))
    }

    /// What VoiceOver reads instead of ninety marks: the range and the stated mean.
    static func accessibilitySummary(_ trend: NutrientTrend) -> String {
        let values = trend.points.compactMap(\.value)
        guard let low = values.min(), let high = values.max() else {
            return "Nothing logged in this range."
        }
        var text = "From \(Formatters.amount(low, unit: trend.nutrient.unit)) to \(Formatters.amount(high, unit: trend.nutrient.unit))"
        if let mean = trend.completeDayMean {
            text += ", mean \(Formatters.amount(mean, unit: trend.nutrient.unit)) on a complete day"
        }
        return text + "."
    }
}

/// The figure under the crosshair, for one day.
private struct CrosshairLabel: View {
    let point: TrendPoint
    let unit: NutrientUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(point.day, format: .dateTime.day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(point.value.map { Formatters.amount($0, unit: unit) } ?? "Nothing logged")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(CoverageStrip.name(point.state))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
