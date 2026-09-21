import SwiftUI

/// One recipe or stored food in the Add sheet: name, the amount used last time and
/// energy per unit ("per 100 g" for a food, "per serving" for a recipe).
struct ChoiceRow: View {
    let choice: FoodChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(choice.name)
            HStack(spacing: 6) {
                if let last = choice.lastAmount {
                    Text("Last \(choice.amountText(last))")
                }
                Text("\(Formatters.amount(choice.perUnit.energy, unit: .kilocalorie)) per \(choice.unitText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
