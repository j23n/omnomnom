import Foundation
import SwiftData
import SwiftUI

/// The field at the bottom of Today: one line in, a meal out.
///
/// Always there, with no sheet to open first. The whole redesign rests on this being
/// the shortest thing on the screen to reach, so it sits in the safe-area bar where the
/// Add button used to be, within a thumb's reach, and the Add sheet becomes the second
/// way in rather than the first.
///
/// Dictation is the keyboard's own microphone key and costs nothing to support. A
/// hold-to-talk control would need the microphone and speech-recognition permissions,
/// and it is not worth asking for those until this has shown whether a hands-free path
/// is actually wanted.
///
/// What sits above the field depends on whether anything has been typed: the usual lines
/// while it is empty, the parse once it is not. The two can never be on screen together,
/// which is deliberate — the field says either "here is what you normally type" or "here
/// is what I made of what you are typing", never both at once.
struct ComposerView: View {
    @Bindable var model: ComposerModel
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFocused, model.line.isEmpty {
                ComposerSuggestions(onPick: fill)
            }
            if !model.preview.isEmpty, isFocused {
                PreviewChips(items: model.preview)
            }
            HStack(spacing: 8) {
                TextField("What did you eat?", text: $model.line, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .accessibilityLabel("What did you eat")
                    .accessibilityHint("Type or dictate a meal, such as oats, banana, coffee")
                    .toolbar {
                        // The way out of the field, and the only one. A vertical field
                        // spends Return on a newline — which this field wants, since a
                        // newline separates foods exactly as a comma does — so the
                        // keyboard grows no Done key of its own and `onSubmit` never
                        // fires from it. Without this button there was no way to put the
                        // keyboard away at all once the field had been tapped.
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isFocused = false }
                        }
                    }
                submit
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(in: Capsule())
        }
        .readableColumn(ReadableColumn.control)
        .animation(.default, value: model.preview)
    }

    private var submit: some View {
        Button(action: onSubmit) {
            if model.isResolving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.up")
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .disabled(!model.canSubmit)
        .accessibilityLabel(model.isResolving ? "Working" : "Log this line")
    }

    /// Takes a suggested line as though it had been typed, and resolves it at once.
    ///
    /// The text is left in the field rather than cleared, so a line that resolves to
    /// nothing is still there to edit. Focus goes because the sheet is about to cover the
    /// keyboard, and a keyboard left standing behind it is only something to dismiss
    /// twice.
    private func fill(_ line: String) {
        model.line = line
        isFocused = false
        onSubmit()
    }
}

/// What this person usually types at this hour, offered once the field is focused and
/// still empty.
///
/// Not a saved-meals list, and built so it cannot be mistaken for one: nothing here is
/// named, edited, reordered or deleted, and the only way a line gets in is by being
/// logged again. "Recents" would promise a list the user owns and therefore has to tend,
/// so the heading is a plain sentence instead of a section title.
///
/// Nothing is offered before the field is focused. Today is a record of what was eaten,
/// and a proposal sitting on it unasked would turn the screen into a prompt. Tapping the
/// field is the moment the user has asked.
///
/// The ranking is the widget's, on purpose the same one: most logged first, most recent
/// breaking a tie, with the lines last logged in this hour's slot ahead of the rest. Two
/// lines, because what this is for is the one line you were about to type, not a history
/// to browse — everything the app remembers is in Settings, under remembered lines.
private struct ComposerSuggestions: View {
    /// Fills the field with this line and sends it straight down the recall path.
    let onPick: (String) -> Void
    /// The clock the slot is read from. Fixed by previews, so a canvas shows breakfast
    /// lines whatever time of day it is opened at.
    var now: Date = .now

    @Query(sort: \Phrase.useCount, order: .reverse) private var phrases: [Phrase]

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // The heading the mock asks for, word for word. "You usually have this
                // for breakfast" is the baseline proposal on Today and means "shall I log
                // this"; this one means "shall I type this", and the two must not sound
                // alike.
                Text("You usually type")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(suggestions) { phrase in
                    row(phrase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Glass, as the banner above the composer is, because this also floats over
            // the day's rows rather than sitting on a background of its own. The mock's
            // heading sits outside the card; here it goes inside, where it stays legible
            // over whatever has been scrolled under it.
            .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// At most two lines: the most logged, with this hour's slot first.
    private var suggestions: [Phrase] {
        let slot = MealSlot.inferred(from: now)
        // The widget's order: a line eaten daily outranks one eaten twice yesterday.
        // `isRecallable` reads a relationship and so cannot be a fetch predicate, which
        // is why the filtering happens here rather than in the query.
        let ranked = phrases
            .filter(\.isRecallable)
            .sorted {
                $0.useCount == $1.useCount ? $0.lastUsed > $1.lastUsed : $0.useCount > $1.useCount
            }
        // Preferred, not required. Someone who has only ever logged breakfasts should
        // still be offered them at four in the afternoon, and that is also what the first
        // week of use looks like from here.
        let forSlot = ranked.filter { $0.lastSlot == slot }
        let others = ranked.filter { $0.lastSlot != slot }
        return Array((forSlot + others).prefix(Self.capacity))
    }

    /// Two, per the design. A third line would make this a list to read instead of a pair
    /// to recognise, and it sits over the day's own rows, which it must not bury.
    private static let capacity = 2

    private func row(_ phrase: Phrase) -> some View {
        Button {
            onPick(phrase.text)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase.text)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(Self.countText(phrase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                // Tapping leads somewhere — the line is read back on the sheet before
                // anything is logged — so it says so.
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Fills the field with this line and reads it back before anything is logged")
    }

    /// "Logged 29 times", in the words the remembered-lines list already uses.
    ///
    /// The mock reads the count as "29 mornings", and that would be a figure the app does
    /// not hold: a phrase keeps one total count and the slot it was last logged in, never
    /// a count per slot. Rather than invent one, the count says what it is, and the slot
    /// shows only in which lines got picked.
    private static func countText(_ phrase: Phrase) -> String {
        phrase.useCount == 1 ? "Logged once" : "Logged \(phrase.useCount) times"
    }
}

/// What the field understood, before anything has been looked up.
///
/// Only the parser has run at this point, so a chip says "this is a food I found in your
/// line" and never "this is a food I have numbers for". It is feedback on the typing,
/// which is why it is plain text rather than tinted: nothing here can be acted on yet.
///
/// Each chip carries the amount its line gave it, and only that. An explicit amount beats
/// a count and a count beats a size word, which is the order of how much they pin down; a
/// fragment that gave none shows none. Filling that gap with the amount the food would
/// resolve to is the one guess this view must not make — nothing has been looked up yet,
/// and a figure that appears before the sentence is finished reads as a decision already
/// taken.
///
/// A count of one is left off. "a banana" and "banana" parse to the same single banana, so
/// "x1" would state nothing the chip does not already say.
///
/// Left out, per the design: energy per chip, which would turn the composer into a
/// calculator and invite correction at a precision the app does not claim. Left out for
/// want of a vocabulary: provenance. The design asks for a clock glyph where the food and
/// its amount were recalled from the last time and a book glyph where they were matched
/// against the database just now, and those glyphs exist nowhere in the app yet — the
/// resolution sheet, which is meant to teach the same pair, does not use them either.
/// Half a vocabulary introduced here would have to be unlearned when the other half
/// arrives.
private struct PreviewChips: View {
    let items: [ParsedItem]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Text(item.name)
                    if let amount = Self.amountText(for: item) {
                        Text(amount)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: .capsule)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenLabel(items))
    }

    /// The amount the chip will use, or `nil` where the line named none.
    private nonisolated static func amountText(for item: ParsedItem) -> String? {
        if let amount = item.amount {
            return Formatters.amount(amount, measure: item.measure)
        }
        if let count = item.count, count != 1 {
            return "×\(Formatters.fieldText(count))"
        }
        // The step the size word stands for, lowercased: the buckets are capitalised on
        // the control that picks one, and this is a fragment of the user's own sentence
        // rather than a control.
        return item.size?.label.lowercased()
    }

    /// Every chip in one sentence, for the one accessibility element the row collapses
    /// into. Built here rather than inside the label's interpolation so the mapping stays
    /// readable.
    private nonisolated static func spokenLabel(_ items: [ParsedItem]) -> String {
        let found = items.count == 1 ? "1 food" : "\(items.count) foods"
        return "Found \(found): \(items.map(spokenItem).joined(separator: ", "))"
    }

    /// The chip as VoiceOver should read it, amount before name, the way the line said
    /// it: "2 eggs" and not "eggs, 2". The symbols are spelled out, since "g" read aloud
    /// is a letter.
    private nonisolated static func spokenItem(_ item: ParsedItem) -> String {
        if let amount = item.amount {
            return "\(Formatters.fieldText(amount)) \(item.measure.spokenName) \(item.name)"
        }
        if let count = item.count, count != 1 {
            return "\(Formatters.fieldText(count)) \(item.name)"
        }
        if let size = item.size {
            return "\(item.name), \(size.label.lowercased())"
        }
        return item.name
    }
}

#if DEBUG
#Preview("Empty", traits: .sizeThatFitsLayout) {
    ComposerView(model: ComposerModel()) {}
        .padding()
}

#Preview("Mid sentence", traits: .sizeThatFitsLayout) {
    let model = ComposerModel()
    model.line = "oats, banana, large coffee"
    return ComposerView(model: model) {}
        .padding()
}

#Preview("Working", traits: .sizeThatFitsLayout) {
    let model = ComposerModel()
    model.line = "a pancake with oats, peanut butter and banana"
    model.isResolving = true
    return ComposerView(model: model) {}
        .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    let model = ComposerModel()
    model.line = "oats, banana, coffee"
    return ComposerView(model: model) {}
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}

// The chips and the usual lines are previewed on their own because both need the field
// to be focused and a preview cannot focus it. The parser runs for real here, so what the
// canvas shows is what a line of typing actually produces.

#Preview("Chips with amounts", traits: .sizeThatFitsLayout) {
    PreviewChips(items: LineParser.parse("200g rice, 2 eggs, a banana, large coffee, peanut b"))
        .padding()
}

#Preview("Chips at accessibility 5", traits: .sizeThatFitsLayout) {
    PreviewChips(items: LineParser.parse("200g rice, 2 eggs, a banana, large coffee, peanut b"))
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Usual lines, morning", traits: .sizeThatFitsLayout) {
    ComposerSuggestions(onPick: { _ in }, now: previewHour(8))
        .padding()
        .previewEnvironment(container: usualLinesContainer())
}

#Preview("Usual lines, nothing for this slot", traits: .sizeThatFitsLayout) {
    ComposerSuggestions(onPick: { _ in }, now: previewHour(23))
        .padding()
        .previewEnvironment(container: usualLinesContainer())
}

// Fixed rather than sized to fit, because the point of this one is that an empty store
// draws nothing at all — not even the heading — and a view of no height is hard to see.
#Preview("Usual lines, nothing remembered", traits: .fixedLayout(width: 390, height: 120)) {
    ComposerSuggestions(onPick: { _ in }, now: previewHour(8))
        .padding()
        .previewEnvironment(seed: .empty)
}

/// Today at `hour` o'clock, so a preview shows the slot it means rather than the slot the
/// canvas happens to be opened in.
private func previewHour(_ hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 5, second: 0, of: .now) ?? .now
}

/// Three remembered lines: two breakfasts, and a lunch logged more often than either, so
/// the slot preference shows as a preference rather than as a side effect of the counts.
/// At 23:00 the slot is a snack, which none of them is, and the fallback shows instead.
@MainActor
private func usualLinesContainer() -> ModelContainer {
    let container = PreviewStore.container(seed: .typicalDay)
    let context = container.mainContext
    guard let food = PreviewStore.foods(in: container).first else { return container }

    /// `remember` counts the one use it writes, so the count is set straight afterwards
    /// rather than by calling it twenty-nine times.
    func record(_ line: String, times: Int, slot: MealSlot) {
        let item = PhraseDraftItem(name: food.name, amount: 50, food: food)
        // `try?` over a call that already returns an optional nests two levels, hence the
        // second unwrap.
        if let remembered = try? Phrase.remember(line: line, items: [item], in: context, slot: slot),
           let phrase = remembered {
            phrase.useCount = times
        }
    }

    record("oats, banana, milk, coffee", times: 29, slot: .breakfast)
    record("rye bread with butter and cheese", times: 11, slot: .breakfast)
    record("chicken salad", times: 40, slot: .lunch)
    try? context.save()
    return container
}
#endif
