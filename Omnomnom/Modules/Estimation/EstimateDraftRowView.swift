import SwiftUI

/// One editable item: name, grams, the eight values, and a remove button. Values are
/// for the portion, so the fields are labelled with the unit alone, never "per 100 g".
struct EstimateDraftRowView: View {
    @Binding var row: EstimateDraftRow
    let onRemove: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $row.name)
                    .accessibilityLabel("Food name")
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(row.trimmedName.isEmpty ? "item" : row.trimmedName)")
            }
            HStack(spacing: 4) {
                Text("Portion")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $row.gramsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(row.isGramsInvalid ? Color.red : Color.primary)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Portion in grams")
                Text("g")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    EstimateValueField(nutrient: nutrient, row: $row)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// One small value field with its short name before and its unit after.
private struct EstimateValueField: View {
    let nutrient: Nutrient
    @Binding var row: EstimateDraftRow

    private var text: Binding<String> {
        Binding(
            get: { row.text(for: nutrient) },
            set: { row.setText($0, for: nutrient) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(nutrient.shortName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            TextField("unknown", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.callout)
                .foregroundStyle(row.isInvalid(nutrient) ? Color.red : Color.primary)
                .frame(maxWidth: 72)
                .accessibilityLabel("\(nutrient.displayName) for this portion, in \(nutrient.unit.symbol)")
            Text(nutrient.unit.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
