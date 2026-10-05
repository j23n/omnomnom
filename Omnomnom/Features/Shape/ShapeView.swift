import SwiftData
import SwiftUI

/// What the log adds up to over time, and the run that gathers it.
///
/// Called Shape rather than Trends. A trend is a line going somewhere, which is a thing to
/// be pleased or displeased about; the shape of what someone eats is a description. The
/// screen says what happened and leaves the verdict to the person reading it.
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
struct ShapeView: View {
    @Environment(\.healthObserving) private var health
    @Environment(\.modelContext) private var context
    @State private var model = TrendsModel()
    /// The run, read locally and cheaply, for the row that leads to its own screen.
    @State private var runModel = RunModel()
    @AppStorage(SamplingCadence.key) private var cadenceRaw = SamplingCadence.standard.rawValue
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
                    NavigationLink {
                        RunView()
                    } label: {
                        RunSummaryRow(run: runModel.run)
                    }
                } footer: {
                    Text("Days you answered, in a row. Never days eaten well.")
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
            .navigationTitle("Shape")
            .overlay {
                if model.isLoading, model.trends.isEmpty {
                    ProgressView()
                }
            }
            .task(id: model.range) {
                model.load(health: health, context: context)
            }
            .task(id: cadenceRaw) {
                runModel.load(
                    context: context,
                    cadence: SamplingCadence(rawValue: cadenceRaw) ?? .standard
                )
            }
        }
    }
}

#if DEBUG
#Preview("Shape") {
    ShapeView()
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Nothing logged") {
    ShapeView()
        .previewEnvironment(seed: .empty)
}

#Preview("Dark") {
    ShapeView()
        .previewEnvironment(seed: .typicalDay)
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    ShapeView()
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
