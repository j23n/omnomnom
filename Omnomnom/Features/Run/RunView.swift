import DeveloperToolsSupport
import Foundation
import os
import SwiftData
import SwiftUI

/// Days answered in a row, and the month they sit in.
///
/// The one screen in the app with a big friendly number on it, and the number is a count of
/// days *answered* — never days eaten well. What it rewards is telling the app what you
/// ate, which is the only thing the app can ask for without taking a view on a diet. A
/// skipped meal is an answer. A day the cadence did not ask about is stepped over. Today
/// being unanswered is just the day not being over.
///
/// Nothing here can go down for the wrong reason, which is the whole design: `best` is
/// never touched by a gap, and the only prompt is for a day still inside the grace window,
/// where closing it is a save rather than a chore.
struct RunView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SamplingCadence.key) private var cadenceRaw = SamplingCadence.standard.rawValue
    @State private var model = RunModel()

    private var cadence: SamplingCadence {
        SamplingCadence(rawValue: cadenceRaw) ?? .standard
    }

    var body: some View {
        List {
            Section {
                numbers
            } footer: {
                Text("Days answered, not days eaten well. A meal you say you skipped is answered.")
            }
            if let open = model.run.open {
                Section {
                    openDay(open)
                }
            }
            Section(Self.monthTitle(model.month)) {
                grid
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        """
                        A full ring is a day answered, and how much of it is drawn is how \
                        many of the four meals were. Grey is a day taken from your usual one.
                        """
                    )
                    Text(cadence.explanation)
                }
            }
        }
        .navigationTitle("The run")
        .task(id: cadenceRaw) {
            model.load(context: context, cadence: cadence)
        }
    }

    /// The two figures, side by side, in the rounded face. The only place in the app a
    /// number is set this large: it is the one screen whose subject *is* a number.
    private var numbers: some View {
        HStack(alignment: .top, spacing: 24) {
            figure(model.run.current, caption: model.run.current == 1 ? "day running" : "days running")
            figure(model.run.best, caption: "your best")
        }
        .padding(.vertical, 4)
    }

    private func figure(_ value: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }

    /// The one prompt: a day still answerable, and what answering it is worth.
    ///
    /// It says what closing the day claims, because that is what the tap means and the
    /// claim is about food rather than about a streak. A run is not a reason to assert
    /// something untrue about a Tuesday.
    private func openDay(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Formatters.dayTitle(day)) is still open")
                .font(.headline)
            Text("Closing it says that is everything you ate that day. The run holds at \(model.run.current + 1).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Close it") { close(day) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(.vertical, 4)
    }

    /// The month as marks, seven across, which is what makes a week a row.
    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
            ForEach(model.month) { day in
                VStack(spacing: 4) {
                    DayMarkView(
                        answers: day.answers,
                        composition: day.composition,
                        isAssumed: day.state == .assumed,
                        size: 32
                    )
                    .accessibilityHidden(true)
                    Text(day.day, format: .dateTime.day())
                        .font(.caption2)
                        .foregroundStyle(day.isAsked ? .secondary : .tertiary)
                        .monospacedDigit()
                }
                .opacity(day.isAsked ? 1 : 0.55)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(for: day))
            }
        }
        .padding(.vertical, 4)
    }

    /// "October", or the month the grid is actually showing.
    static func monthTitle(_ month: [RunDay]) -> String {
        guard let day = month.last?.day else { return "This month, meal by meal" }
        return "\(day.formatted(.dateTime.month(.wide))), meal by meal"
    }

    /// What a cell says when it is read aloud: the date, then the mark's own sentence,
    /// then whether the day was one the app asked about.
    static func label(for day: RunDay) -> String {
        var parts = [
            day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
            DayMarkView.label(
                answers: day.answers, composition: day.composition, isAssumed: day.state == .assumed
            )
        ]
        if !day.isAsked {
            parts.append("Not a day you are asked about.")
        }
        return parts.joined(separator: " ")
    }

    /// Marks the open day as everything that was eaten, then reads the run again.
    private func close(_ day: Date) {
        do {
            try DayRecord.setComplete(true, for: day, in: context)
            try context.save()
        } catch {
            AppLog.store.error("could not close the day: \(error.localizedDescription, privacy: .public)")
        }
        model.load(context: context, cadence: cadence)
    }
}

/// The run as one row, which is how Shape leads to it.
struct RunSummaryRow: View {
    let run: DayRun

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("The run")
            Text(Self.detail(run))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "17 days answered · best 34", or what it says before there is a run at all.
    static func detail(_ run: DayRun) -> String {
        guard run.current > 0 || run.best > 0 else { return "No days answered yet" }
        let days = run.current == 1 ? "1 day answered" : "\(run.current) days answered"
        return "\(days) · best \(run.best)"
    }
}

#if DEBUG
#Preview("The run") {
    NavigationStack {
        RunView()
    }
    .previewEnvironment(seed: .typicalDay)
}

#Preview("Nothing logged") {
    NavigationStack {
        RunView()
    }
    .previewEnvironment(seed: .empty)
}

#Preview("Three days a week") {
    NavigationStack {
        RunView()
    }
    .previewEnvironment(seed: .typicalDay, defaults: PreviewDefaults.threeDaysAWeek)
}

#Preview("Accessibility 5") {
    NavigationStack {
        RunView()
    }
    .previewEnvironment(seed: .typicalDay)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("The row", traits: .sizeThatFitsLayout) {
    List {
        RunSummaryRow(run: DayRun(current: 17, best: 34, open: nil))
        RunSummaryRow(run: DayRun(current: 1, best: 1, open: nil))
        RunSummaryRow(run: .empty)
    }
}
#endif
