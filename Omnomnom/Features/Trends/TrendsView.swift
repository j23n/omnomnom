import SwiftData
import SwiftUI

/// What the log adds up to over time.
///
/// This reverses an earlier decision to leave history to the Health app. The goal is an
/// overview of nutrition in broad strokes over months, and an app that cannot show one is
/// not doing its job, whatever the Health app also draws. The earlier reasoning — that
/// trends would duplicate data this app does not own — is answered by reading them from
/// the place that does own them.
///
/// All eight nutrients are charted. Today's headline has to pick four because a phone's
/// width forces it; a scrolling screen has no such constraint, so limiting this one would
/// be a judgement about which nutrients deserve a chart rather than a consequence of
/// anything.
struct TrendsView: View {
    @Environment(\.healthObserving) private var health
    @Environment(\.modelContext) private var context
    @State private var model = TrendsModel()
    /// Shared by every chart, so one gesture reads them all at the same date.
    @State private var selected: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $model.range) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    // The basis is stated once, above everything, rather than under each
                    // of eight charts where the same sentence eight times would read as
                    // decoration instead of as a fact governing the screen.
                    Text(model.basis.sentence)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let note = model.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let energy = model.trends.first(where: { $0.nutrient == .energy }) {
                    Section {
                        NutrientChart(trend: energy, selected: $selected)
                        // Second, not last: with eight charts, putting coverage at the
                        // bottom means the reader meets every line before learning how
                        // many days they rest on, and a confident reading of a sparse
                        // month is the one conclusion this screen must not produce.
                        CoverageStrip(points: model.coverage)
                    }
                }

                Section {
                    ForEach(model.trends.filter { $0.nutrient != .energy }) { trend in
                        NutrientChart(trend: trend, selected: $selected)
                    }
                }

                Section {
                    DisclosureGroup("The days behind these lines") {
                        ForEach(model.coverage.reversed()) { point in
                            LabeledContent {
                                Text(point.value.map { Formatters.amount($0, unit: .kilocalorie) } ?? "—")
                                    .monospacedDigit()
                            } label: {
                                Text(point.day, format: .dateTime.day().month(.abbreviated).year())
                                Text(CoverageStrip.name(point.state))
                            }
                        }
                    }
                } footer: {
                    Text("Read from Health, which counts every source once. What a complete day is comes from this app.")
                }
            }
            .navigationTitle("Trends")
            .overlay {
                if model.isLoading, model.trends.isEmpty {
                    ProgressView()
                }
            }
            .task(id: model.range) {
                model.load(health: health, context: context)
            }
        }
    }
}

#if DEBUG
#Preview("Trends") {
    TrendsView()
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Nothing logged") {
    TrendsView()
        .previewEnvironment(seed: .empty)
}

#Preview("Dark") {
    TrendsView()
        .previewEnvironment(seed: .typicalDay)
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    TrendsView()
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
