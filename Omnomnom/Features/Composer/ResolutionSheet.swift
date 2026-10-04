import SwiftUI

/// What the line resolved to, before it is logged.
///
/// Five states have to tell themselves apart here and no colour may encode a verdict,
/// which is the hardest constraint in the app. They are collapsed into three tiers the
/// layout can carry: settled rows are quiet and show only a name, an amount and where
/// they came from; a row worth a glance carries a chevron and reads differently
/// underneath; a row that blocks loses the Log button and gains a control that cannot be
/// ignored.
///
/// The count above the button is doing most of that work. Row height is a weak signal in
/// a short list and nearly worthless at accessibility sizes, so a sentence saying how
/// many rows want a look is what carries the middle tier. It is the one element on this
/// screen that most needs trying on a real person.
struct ResolutionSheet: View {
    let resolution: LineResolution
    let onChange: (ResolvedRow) -> Void
    let onRemove: (ResolvedRow) -> Void
    let onPick: (ResolvedRow) -> Void
    /// Logs the line into the meal and at the time the sheet is showing.
    ///
    /// Carried out rather than decided by the caller, because this screen is the one place
    /// the two are visible and the only place they can be changed. Until it was, every
    /// line was logged into whichever meal the hour implied, with no way to say otherwise.
    let onLog: (MealSlot, Date) -> Void

    /// The meal and the moment, defaulted the way the Quantity sheet defaults them.
    ///
    /// One rule for this, not two: the selected day at the current wall-clock time, so a
    /// line logged into the past keeps a sensible hour and the meal that hour implies. The
    /// slot does not follow the time once it has been shown, because a user who sets one
    /// of them has said something about it and the screen should not then argue.
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date

    init(
        resolution: LineResolution,
        day: Date,
        onChange: @escaping (ResolvedRow) -> Void,
        onRemove: @escaping (ResolvedRow) -> Void,
        onPick: @escaping (ResolvedRow) -> Void,
        onLog: @escaping (MealSlot, Date) -> Void
    ) {
        self.resolution = resolution
        self.onChange = onChange
        self.onRemove = onRemove
        self.onPick = onPick
        self.onLog = onLog
        let timestamp = QuantitySheet.defaultTimestamp(on: day)
        _timestamp = State(initialValue: timestamp)
        _mealSlot = State(initialValue: MealSlot.inferred(from: timestamp))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(resolution.rows) { row in
                        ResolutionRowView(
                            row: row,
                            checked: resolution.wasChecked,
                            onPick: { onPick(row) },
                            onChange: onChange
                        )
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                onRemove(row)
                            }
                        }
                    }
                } footer: {
                    if !resolution.wasChecked, resolution.rows.contains(where: { $0.origin == .database }) {
                        // A description of what happened, not an apology for what did
                        // not. Either every match on a line was checked or none was, so
                        // this belongs to the screen rather than to any row.
                        Text("Matched by name. Your device does not check matches.")
                    }
                }

                if let energy = resolution.total.energy {
                    Section("This line") {
                        LabeledContent("Energy", value: Formatters.amount(energy, unit: .kilocalorie))
                    }
                }

                Section {
                    Picker("Meal", selection: $mealSlot) {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Text(slot.displayName).tag(slot)
                        }
                    }
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Log this")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .bottom) {
                footer
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let note = attention {
                Text(note)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                onLog(mealSlot, timestamp)
            } label: {
                Text("Log")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(!resolution.canLog)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn(ReadableColumn.control)
    }

    /// The one line carrying the middle tier, or what is stopping the log.
    private var attention: String? {
        if resolution.blockingCount > 0 {
            return resolution.blockingCount == 1
                ? "1 row needs a food before you can log this."
                : "\(resolution.blockingCount) rows need a food before you can log this."
        }
        guard resolution.glanceCount > 0 else { return nil }
        return resolution.glanceCount == 1
            ? "1 row worth a glance."
            : "\(resolution.glanceCount) rows worth a glance."
    }
}

#if DEBUG
private func previewRow(
    _ name: String, kcal: Double, amount: Double, origin: RowOrigin,
    confidence: MatchConfidence, matched: Bool = true
) -> ResolvedRow {
    ResolvedRow(
        name: name,
        choice: matched
            ? FoodChoice(
                source: .bundled(id: abs(name.hashValue % 10_000)), name: name,
                perUnit: Nutrition(energy: kcal, protein: 8, carbohydrates: 60, fatTotal: 7)
            )
            : nil,
        amount: amount,
        bucket: origin.isRecalled ? .usual : nil,
        origin: origin,
        confidence: confidence
    )
}

#Preview("From a line logged before") {
    ResolutionSheet(
        resolution: LineResolution(
            line: "oats with a banana",
            rows: [
                previewRow("Oats, rolled", kcal: 370, amount: 40, origin: .phrase, confidence: .settled),
                previewRow("Banana, raw", kcal: 90, amount: 120, origin: .phrase, confidence: .settled),
            ],
            wasChecked: false
        ),
        day: .now,
        onChange: { _ in }, onRemove: { _ in }, onPick: { _ in }, onLog: { _, _ in }
    )
}

#Preview("Three tiers at once") {
    ResolutionSheet(
        resolution: LineResolution(
            line: "oats, flat white, something unusual",
            rows: [
                previewRow("Oats, rolled", kcal: 370, amount: 40, origin: .item, confidence: .settled),
                previewRow("Coffee with milk", kcal: 45, amount: 200, origin: .database, confidence: .probable),
                previewRow("something unusual", kcal: 0, amount: 0, origin: .database, confidence: .unsure, matched: false),
            ],
            wasChecked: true
        ),
        day: .now,
        onChange: { _ in }, onRemove: { _ in }, onPick: { _ in }, onLog: { _, _ in }
    )
}

#Preview("Unchecked device") {
    ResolutionSheet(
        resolution: LineResolution(
            line: "oats, banana",
            rows: [
                previewRow("Oats, rolled", kcal: 370, amount: 40, origin: .database, confidence: .probable),
                previewRow("Banana, raw", kcal: 90, amount: 120, origin: .database, confidence: .settled),
            ],
            wasChecked: false
        ),
        day: .now,
        onChange: { _ in }, onRemove: { _ in }, onPick: { _ in }, onLog: { _, _ in }
    )
}
#endif
