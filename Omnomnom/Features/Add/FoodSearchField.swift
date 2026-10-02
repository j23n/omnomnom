import SwiftUI

/// The search field at the top of the food search screen.
///
/// Deliberately not `.searchable`: that bar arrives after the list has already
/// drawn and takes the navigation bar with it, so opening the screen was a list,
/// then a bar sliding in, then a keyboard. Here the field is part of the layout
/// from the first frame and the keyboard is the only thing that moves.
struct FoodSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.secondary, in: Capsule())
        .padding(.horizontal)
        .padding(.bottom, 8)
        .readableColumn()
    }
}

#if DEBUG
private struct FoodSearchFieldPreview: View {
    @State private var text: String
    @FocusState private var focused: Bool

    init(text: String) {
        _text = State(initialValue: text)
    }

    var body: some View {
        FoodSearchField(text: $text, prompt: "Search foods", isFocused: $focused)
    }
}

#Preview("Empty", traits: .sizeThatFitsLayout) {
    FoodSearchFieldPreview(text: "")
}

#Preview("Typed", traits: .sizeThatFitsLayout) {
    FoodSearchFieldPreview(text: "rolled oats")
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 120)) {
    FoodSearchFieldPreview(text: "rolled oats")
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    FoodSearchFieldPreview(text: "rolled oats")
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
