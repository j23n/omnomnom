import SwiftUI

/// One per-100 field of the food editor with its unit; energy is marked as required
/// in the placeholder, and text that does not parse turns red. VoiceOver names the
/// reference the draft is currently on, "per 100 grams" or "per 100 millilitres".
struct NutrientField: View {
    let nutrient: Nutrient
    @Binding var draft: CustomFoodDraft

    private var text: Binding<String> {
        Binding(
            get: { draft.text(for: nutrient) },
            set: { draft.setText($0, for: nutrient) }
        )
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(nutrient == .energy ? "required" : "unknown", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(draft.isInvalid(nutrient) ? Color.red : Color.primary)
                    .accessibilityLabel(
                        "\(nutrient.displayName) per 100 \(draft.measure.spokenName), in \(nutrient.unit.symbol)"
                    )
                Text(nutrient.unit.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(nutrient.displayName)
        }
    }
}
