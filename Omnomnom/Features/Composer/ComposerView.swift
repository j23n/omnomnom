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
struct ComposerView: View {
    @Bindable var model: ComposerModel
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
}

/// What the field understood, before anything has been looked up.
///
/// Only the parser has run at this point, so a chip says "this is a food I found in your
/// line" and never "this is a food I have numbers for". It is feedback on the typing,
/// which is why it is plain text rather than tinted: nothing here can be acted on yet.
private struct PreviewChips: View {
    let items: [ParsedItem]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                Text(item.name)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: .capsule)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Found \(items.count == 1 ? "1 food" : "\(items.count) foods"): \(items.map(\.name).joined(separator: ", "))")
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
#endif
