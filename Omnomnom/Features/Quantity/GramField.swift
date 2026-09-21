import SwiftUI

/// The canonical amount field: decimal pad, grams only, VoiceOver reads the unit.
struct GramField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .focused(isFocused)
                .accessibilityLabel("Grams")
                .accessibilityValue(text.isEmpty ? "no amount" : "\(text) grams")
            Text("g")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
