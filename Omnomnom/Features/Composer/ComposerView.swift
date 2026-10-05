import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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
    @State private var isCameraPresented = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFocused, model.line.isEmpty {
                ComposerSuggestions(onPick: fill)
            }
            if model.image != nil {
                AttachedPhoto(data: model.image) { model.image = nil }
            }
            HStack(spacing: 8) {
                TextField("What did you eat?", text: $model.line, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(send)
                    .accessibilityLabel("What did you eat")
                    .accessibilityHint("Type or dictate a meal, such as oats, banana, coffee")
                camera
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(in: Capsule())
        }
        .readableColumn(ReadableColumn.control)
        .animation(.default, value: model.image)
    }

    /// One control, one place: send the line, or put the keyboard away.
    ///
    /// A keyboard toolbar used to hold the way out. Inside a bottom inset it rendered in the
    /// wrong place and sometimes over the field itself, and a vertical field spends Return
    /// on a newline — which this field wants, since a newline separates foods as a comma
    /// does — so there was no Done key either. Nothing about the field's own corner moves,
    /// which is what makes it findable: with something to send it sends, and with an empty
    /// field and a keyboard up it closes the keyboard.
    @ViewBuilder private var trailing: some View {
        if isFocused, !model.canSubmit, !model.isResolving {
            Button(action: putKeyboardAway) {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close the keyboard")
        } else {
            submit
        }
    }

    private var submit: some View {
        Button(action: send) {
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

    /// Sends what is in the field, with the keyboard put away first.
    ///
    /// The order is the fix for a keyboard that came back on its own. UIKit hands the
    /// keyboard back to whatever held it when a pushed screen pops, so a field still
    /// focused when the sign-off screen went up got one again the moment the meal was
    /// logged — and SwiftUI, never told of a focus change, laid this bar out as though
    /// there were no keyboard, which left it standing over the field and over the only
    /// control that puts it away. Resigning before the push leaves nothing to hand back.
    ///
    /// Every way in goes through here: the button, the Return key, and a suggested line.
    private func send() {
        isFocused = false
        onSubmit()
    }

    /// Puts the keyboard down, by both routes.
    ///
    /// `isFocused` is the one that normally does it. The resign goes out as well because
    /// the field can be holding the keyboard while SwiftUI believes nothing is focused,
    /// and in that state clearing a focus that already reads false changes nothing — which
    /// is exactly the state this control exists for.
    private func putKeyboardAway() {
        isFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// The camera, and the library when there is no camera.
    ///
    /// Inside the field rather than beside it, because it is another way of answering the
    /// same question: a picture of a plate and a sentence about it are one input, and the
    /// model takes either. A separate camera feature is what this replaced.
    @ViewBuilder private var camera: some View {
        if hasCamera {
            Button { isCameraPresented = true } label: {
                Image(systemName: "camera")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Add a photo of the meal")
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraCaptureView(
                    onCapture: { image in
                        isCameraPresented = false
                        model.image = image.jpegData(compressionQuality: 0.9)
                    },
                    onCancel: { isCameraPresented = false }
                )
                .ignoresSafeArea()
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Add a photo of the meal")
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    model.image = try? await item.loadTransferable(type: Data.self)
                    pickerItem = nil
                }
            }
        }
    }

    private var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Takes a suggested line as though it had been typed, and resolves it at once.
    ///
    /// The text is left in the field rather than cleared, so a line that resolves to
    /// nothing is still there to edit. The rest is `send`'s doing: the keyboard goes
    /// before the screen does, since one left standing behind it is only something to
    /// dismiss twice.
    private func fill(_ line: String) {
        model.line = line
        send()
    }
}

/// The photograph waiting to be sent, and the way to change your mind about it.
///
/// Above the field rather than inside it: a thumbnail squeezed into a capsule beside two
/// buttons is unreadable at any type size, and a picture the model is about to be asked
/// about is worth seeing before it is sent. It is the only thing on this screen that can be
/// removed without typing, so the control says what it does rather than being a bare cross.
private struct AttachedPhoto: View {
    let data: Data?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PhotoThumbnail(data: data, size: 44)
            Text("Photo attached")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Remove", systemImage: "xmark") { onRemove() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove the photo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
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

// The usual lines are previewed on their own because they need the field to be focused
// and a preview cannot focus it.

#Preview("A photo attached", traits: .sizeThatFitsLayout) {
    AttachedPhoto(data: PreviewStore.samplePhoto) {}
        .padding()
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
        // One unwrap, not two: `try?` over a throwing call that already returns an
        // optional flattens rather than nesting, so this is a `Phrase?`.
        if let phrase = try? Phrase.remember(line: line, items: [item], in: context, slot: slot) {
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
