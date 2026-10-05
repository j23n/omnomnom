import SwiftUI

/// Why the food search screen is up over the sign-off screen. One slot, so adding and
/// replacing can never fight over it.
private nonisolated enum FoodPick: Identifiable, Hashable, Sendable {
    /// Changing the food on a row the line produced.
    case replacing(ResolvedRow)
    /// Adding a food of the user's own, which the line may never have mentioned.
    case adding

    var id: String {
        switch self {
        case .replacing(let row): "replace-\(row.id)"
        case .adding: "add"
        }
    }
}

/// What the line resolved to, before it is logged.
///
/// A pushed screen and not a sheet. Signing off a meal means changing a food and choosing a
/// weight, and both want something on top of this — a search screen, a keypad. A sheet
/// cannot host those: whatever presented the sheet owns the next presentation, so the food
/// picker was being put up by the screen underneath while this one was in the way. Pushing
/// makes this the topmost thing, which is the only arrangement where its own controls work.
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
struct ResolutionScreen: View {
    let resolution: LineResolution
    let onChange: (ResolvedRow) -> Void
    let onRemove: (ResolvedRow) -> Void
    /// Appends a food the user picked, which is the other half of signing off: a model
    /// that names four of the five things on a plate leaves nothing to do about the fifth
    /// otherwise, and the way out used to be to abandon the line and type it again.
    let onAdd: (ResolvedRow) -> Void
    /// Logs the line into the meal and at the time the sheet is showing.
    ///
    /// Carried out rather than decided by the caller, because this screen is the one place
    /// the two are visible and the only place they can be changed. Until it was, every
    /// line was logged into whichever meal the hour implied, with no way to say otherwise.
    let onLog: (MealSlot, Date) -> Void

    /// The meal and the moment, both editable, both defaulted from the meal the model
    /// judged this to be.
    ///
    /// Describing oats at nine in the evening means breakfast, so the slot comes from the
    /// foods and the hour then follows the slot — eight in the morning, not the moment it
    /// was typed. Where nothing judged it, the clock decides as it always did. Either way
    /// `MealSlot.timestamp(on:)` refuses to record a time that has not happened yet.
    ///
    /// Neither follows the other after this. A user who sets one of them has said something
    /// about it, and the screen should not then argue.
    @State private var mealSlot: MealSlot
    @State private var timestamp: Date
    /// The food search screen, when it is up. Presented from here, which is the point of
    /// the screen being pushed: the search screen brings its own navigation and so wants
    /// to be a sheet, and a sheet put up from here lands on top of here.
    @State private var pick: FoodPick?

    init(
        resolution: LineResolution,
        day: Date,
        onChange: @escaping (ResolvedRow) -> Void,
        onRemove: @escaping (ResolvedRow) -> Void,
        onAdd: @escaping (ResolvedRow) -> Void,
        onLog: @escaping (MealSlot, Date) -> Void
    ) {
        self.resolution = resolution
        self.onChange = onChange
        self.onRemove = onRemove
        self.onAdd = onAdd
        self.onLog = onLog
        let slot = resolution.meal ?? MealSlot.inferred(from: QuantitySheet.defaultTimestamp(on: day))
        _mealSlot = State(initialValue: slot)
        _timestamp = State(initialValue: slot.timestamp(on: day))
    }

    var body: some View {
        List {
            Section {
                ForEach(resolution.rows) { row in
                    ResolutionRowView(
                        row: row,
                        checked: resolution.wasChecked,
                        onPick: { pick = .replacing(row) },
                        onChange: onChange
                    )
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            onRemove(row)
                        }
                    }
                }
                // Under the foods rather than in the navigation bar: it belongs to this
                // list, it is read as the end of it, and the bar is where Back is.
                Button {
                    pick = .adding
                } label: {
                    Label("Add a food", systemImage: "plus")
                }
                .accessibilityHint("Searches for a food to add to this meal")
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
        .sheet(item: $pick) { request in
            switch request {
            case .replacing(let row):
                FoodSearchView(mode: .pick(multiple: false, onPick: { choose($0, for: row) }))
            // Several at a time: someone who noticed one missing food often noticed two,
            // and the search screen already stays open and counts them in that mode.
            case .adding:
                FoodSearchView(mode: .pick(multiple: true, onPick: { add($0) }))
            }
        }
    }

    /// Hands a picked food to the row that asked for it, keeping the amount the row already
    /// had: the user changed what the food is, not how much of it there was. A row that had
    /// no food had no amount either, so that one takes what this person last had of it, and
    /// the reference follows the food that won.
    private func choose(_ choice: FoodChoice, for row: ResolvedRow) {
        var updated = row
        updated.choice = choice
        updated.confidence = .settled
        updated.implausible = false
        if updated.amount == 0 {
            updated.amount = choice.lastAmount ?? Self.defaultAmount
        }
        updated.baseAmount = choice.lastAmount
        // Whatever matched this row before, the food on it is now one the user named, and
        // "matched by name" would be a description of something that no longer happened.
        updated.origin = .chosen
        onChange(updated)
        pick = nil
    }

    /// Appends a food of the user's own.
    ///
    /// Settled, with nothing to check: a food someone searched for and tapped is as sure
    /// as this screen gets. The amount is what they last had of it, which is also what
    /// gives the steps something to measure from; a food they have never had starts at
    /// `defaultAmount` with no steps offered, and is edited by typing.
    ///
    /// The search screen stays open afterwards, so the row count grows behind it and
    /// nothing here needs closing.
    private func add(_ choice: FoodChoice) {
        onAdd(ResolvedRow(
            name: choice.name,
            choice: choice,
            amount: choice.lastAmount ?? Self.defaultAmount,
            baseAmount: choice.lastAmount,
            origin: .chosen,
            confidence: .settled
        ))
    }

    /// What a food with no history behind it starts at, as the recipe editor and the
    /// photo estimate's draft both start a new row at.
    ///
    /// The Quantity sheet leaves that field empty instead and waits to be typed into,
    /// which is the better answer where a field is the whole screen. Here the amount is
    /// one control on a row among several, and a row showing nothing where every other
    /// row shows a figure reads as broken rather than as a question.
    private static let defaultAmount = 100.0

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
    // Pushed in the app, so pushed here: the title and the bar belong to a stack.
    NavigationStack {
        ResolutionScreen(
            resolution: LineResolution(
                line: "oats with a banana",
                rows: [
                    previewRow("Oats, rolled", kcal: 370, amount: 40, origin: .phrase, confidence: .settled),
                    previewRow("Banana, raw", kcal: 90, amount: 120, origin: .phrase, confidence: .settled),
                ],
                wasChecked: false
            ),
            day: .now,
            onChange: { _ in }, onRemove: { _ in }, onAdd: { _ in }, onLog: { _, _ in }
        )
    }
}

#Preview("Three tiers at once") {
    // Pushed in the app, so pushed here: the title and the bar belong to a stack.
    NavigationStack {
        ResolutionScreen(
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
            onChange: { _ in }, onRemove: { _ in }, onAdd: { _ in }, onLog: { _, _ in }
        )
    }
}

#Preview("Unchecked device") {
    // Pushed in the app, so pushed here: the title and the bar belong to a stack.
    NavigationStack {
        ResolutionScreen(
            resolution: LineResolution(
                line: "oats, banana",
                rows: [
                    previewRow("Oats, rolled", kcal: 370, amount: 40, origin: .database, confidence: .probable),
                    previewRow("Banana, raw", kcal: 90, amount: 120, origin: .database, confidence: .settled),
                ],
                wasChecked: false
            ),
            day: .now,
            onChange: { _ in }, onRemove: { _ in }, onAdd: { _ in }, onLog: { _, _ in }
        )
    }
}
#endif
